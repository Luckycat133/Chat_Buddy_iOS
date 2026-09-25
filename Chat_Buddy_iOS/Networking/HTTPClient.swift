import Foundation
import os

/// Type-safe HTTP client that:
///   - Injects the bearer token from `AuthSession` on every request.
///   - Decodes the standard error envelope (`APIErrorEnvelope`) on non-2xx.
///   - Surfaces request IDs for log correlation.
///   - Supports idempotency-key for write endpoints (per skill §"Offline behavior").
///
/// Per the iOS skill §"Client boundary":
///   - The client may render, cache, sync, queue mutations, request
///     permissions, and execute approved native actions.
///   - The client must not call hosted chat models, decide AI replies,
///     extract authoritative memory, or simulate relationships.
public actor HTTPClient {
    private let environment: AppEnvironment
    private let session: AuthSession
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = CloudLogger.auth

    /// Invoked once on a 401 before a single retry. The app state wires
    /// this to the token-refresh flow (skill §"Authentication": token
    /// refresh + multi-device revocation). When refresh fails, the handler
    /// clears the session and routes to sign-in; the retry then fails with
    /// the same 401, which is surfaced to the caller.
    private var unauthorizedHandler: (@Sendable () async -> Void)?

    public init(
        environment: AppEnvironment,
        session: AuthSession,
        urlSession: URLSession = .shared,
    ) {
        self.environment = environment
        self.session = session
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractional
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractional
        self.encoder = encoder
    }

    /// Install the 401 → refresh → retry-once hook. Idempotent.
    public func setUnauthorizedHandler(_ handler: @escaping @Sendable () async -> Void) {
        self.unauthorizedHandler = handler
    }

    /// Execute a typed GET.
    public func get<T: Decodable>(
        _ endpoint: APIEndpoint,
        as _: T.Type = T.self,
    ) async throws -> T {
        try await send(endpoint, method: "GET", body: Optional<EmptyBody>.none)
    }

    /// Execute a typed POST/PUT/PATCH/DELETE.
    public func send<B: Encodable, T: Decodable>(
        _ endpoint: APIEndpoint,
        method: String,
        body: B?,
        as _: T.Type = T.self,
    ) async throws -> T {
        try await send(endpoint, method: method, body: body)
    }

    /// Stream variants (SSE) are not part of the P0 client surface; the
    /// realtime channel owns stream delivery.
    public func sendRaw(_ endpoint: APIEndpoint) async throws -> Data {
        let request = try await buildRequest(endpoint, method: "GET", body: Optional<EmptyBody>.none)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, requestId: headerValue(response: response, name: "x-request-id"))
        return data
    }

    private func send<B: Encodable, T: Decodable>(
        _ endpoint: APIEndpoint,
        method: String,
        body: B?,
    ) async throws -> T {
        do {
            return try await perform(endpoint, method: method, body: body)
        } catch let error as APIError where error.code == .unauthorized {
            // Token refresh + retry exactly once — never a loop.
            await unauthorizedHandler?()
            return try await perform(endpoint, method: method, body: body)
        }
    }

    private func perform<B: Encodable, T: Decodable>(
        _ endpoint: APIEndpoint,
        method: String,
        body: B?,
    ) async throws -> T {
        let request = try await buildRequest(endpoint, method: method, body: body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(
            response: response,
            data: data,
            requestId: headerValue(response: response, name: "x-request-id"),
        )
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("decode failed for \(endpoint.path, privacy: .public): \(String(describing: error), privacy: .public)")
            throw APIError(
                code: .internal_,
                message: "decode failed: \(error)",
                status: 502,
                requestId: headerValue(response: response, name: "x-request-id"),
                details: nil,
            )
        }
    }

    private func buildRequest<B: Encodable>(
        _ endpoint: APIEndpoint,
        method: String,
        body: B?,
    ) async throws -> URLRequest {
        guard var components = URLComponents(
            url: environment.apiBaseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false,
        ) else {
            throw APIError(code: .internal_, message: "invalid URL", status: 500, requestId: nil, details: nil)
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw APIError(code: .internal_, message: "invalid URL components", status: 500, requestId: nil, details: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(environment.bundleIdentifier, forHTTPHeaderField: "x-client")
        request.setValue(environment.buildNumber, forHTTPHeaderField: "x-client-build")
        if let idem = endpoint.idempotencyKey {
            request.setValue(idem, forHTTPHeaderField: "idempotency-key")
        }
        if let token = await session.currentAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw APIError(
                    code: .internal_,
                    message: "encode failed: \(error)",
                    status: 500,
                    requestId: nil,
                    details: nil,
                )
            }
        }
        return request
    }

    private func validate(response: URLResponse, data: Data, requestId: String?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200..<300).contains(http.statusCode) { return }
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            throw APIError(
                code: envelope.error.code,
                message: envelope.error.message,
                status: http.statusCode,
                requestId: envelope.error.requestId ?? requestId,
                details: envelope.error.details,
            )
        }
        throw APIError(
            code: .internal_,
            message: "HTTP \(http.statusCode)",
            status: http.statusCode,
            requestId: requestId,
            details: nil,
        )
    }

    private func headerValue(response: URLResponse, name: String) -> String? {
        (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: name)
    }
}

/// Sentinels for endpoints that have no request or response body.
public struct EmptyBody: Codable, Sendable, Equatable {}
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}

extension JSONDecoder.DateDecodingStrategy {
    /// ISO-8601 with optional fractional seconds — matches the server's
    /// `Date.toISOString()` output.
    public static var iso8601WithFractional: JSONDecoder.DateDecodingStrategy {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let d = formatter.date(from: raw) { return d }
            if let d = fallback.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable ISO-8601 date: \(raw)",
            )
        }
    }
}

extension JSONEncoder.DateEncodingStrategy {
    public static var iso8601WithFractional: JSONEncoder.DateEncodingStrategy {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
    }
}