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
    private enum RequestBody {
        case encodable(any Encodable)
        case json(Data)
    }

    private let environment: AppEnvironment
    private let session: AuthSession
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let lifetime: CloudAccountLifetime?
    private let accountId: String?
    private let ownsURLSession: Bool
    private let logger = CloudLogger.auth

    /// Receives the access token the server rejected. A retry requires a
    /// successful refresh for the same authenticated account.
    private var unauthorizedHandler: (@Sendable (String) async -> Bool)?

    public init(
        environment: AppEnvironment,
        session: AuthSession,
        urlSession: URLSession = .shared,
    ) {
        self.init(
            environment: environment,
            session: session,
            urlSession: urlSession,
            lifetime: nil,
            accountId: nil,
            ownsURLSession: false,
        )
    }

    init(
        environment: AppEnvironment,
        session: AuthSession,
        urlSession: URLSession,
        lifetime: CloudAccountLifetime?,
        accountId: String?,
        ownsURLSession: Bool,
    ) {
        self.environment = environment
        self.session = session
        self.urlSession = urlSession
        self.lifetime = lifetime
        self.accountId = accountId
        self.ownsURLSession = ownsURLSession
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractional
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractional
        self.encoder = encoder
    }

    func invalidate() {
        lifetime?.end()
        if ownsURLSession { urlSession.invalidateAndCancel() }
    }

    /// Install the 401 → refresh → retry-once hook. Idempotent.
    public func setUnauthorizedHandler(_ handler: @escaping @Sendable (String) async -> Bool) {
        self.unauthorizedHandler = handler
    }

    /// Execute a typed GET.
    public func get<T: Decodable>(
        _ endpoint: APIEndpoint,
        as _: T.Type = T.self,
    ) async throws -> T {
        try await send(endpoint, method: "GET", requestBody: nil)
    }

    /// Execute a typed POST/PUT/PATCH/DELETE.
    public func send<B: Encodable, T: Decodable>(
        _ endpoint: APIEndpoint,
        method: String,
        body: B?,
        as _: T.Type = T.self,
    ) async throws -> T {
        try await send(endpoint, method: method, requestBody: body.map { .encodable($0) })
    }

    /// Send JSON already encoded by a durable mutation. Retries use the same bytes.
    func sendJSON<T: Decodable>(
        _ endpoint: APIEndpoint,
        method: String,
        body: Data,
        as _: T.Type = T.self,
    ) async throws -> T {
        try await send(endpoint, method: method, requestBody: .json(body))
    }

    /// Stream variants (SSE) are not part of the P0 client surface; the
    /// realtime channel owns stream delivery.
    public func sendRaw(_ endpoint: APIEndpoint) async throws -> Data {
        let request = try await buildRequest(endpoint, method: "GET", body: nil)
        do {
            return try await performRaw(request)
        } catch let error as APIError where error.code == .unauthorized && endpoint.requiresAuth && endpoint.refreshesAuth {
            try await refreshAuthorization(for: request, unauthorized: error)
            let retry = try await buildRequest(endpoint, method: "GET", body: nil)
            return try await performRaw(retry)
        }
    }

    private func performRaw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        try lifetime?.check()
        try validate(response: response, data: data, requestId: headerValue(response: response, name: "x-request-id"))
        return data
    }

    private func refreshAuthorization(for request: URLRequest, unauthorized error: APIError) async throws {
        guard let unauthorizedHandler,
              let authorization = request.value(forHTTPHeaderField: "authorization"),
              authorization.hasPrefix("Bearer ")
        else { throw error }
        try lifetime?.check()
        guard await unauthorizedHandler(String(authorization.dropFirst("Bearer ".count))) else { throw error }
    }

    private func send<T: Decodable>(
        _ endpoint: APIEndpoint,
        method: String,
        requestBody: RequestBody?,
    ) async throws -> T {
        let request = try await buildRequest(endpoint, method: method, body: requestBody)
        do {
            return try await perform(request, endpoint: endpoint)
        } catch let error as URLError where endpoint.replaysLostResponse
            && (error.code == .timedOut || error.code == .networkConnectionLost)
        {
            // The deletion receipt is bound to the original authorization.
            // Reuse the exact request once before reporting an unknown outcome.
            try lifetime?.check()
            return try await perform(request, endpoint: endpoint)
        } catch let error as APIError where error.code == .unauthorized && endpoint.requiresAuth && endpoint.refreshesAuth {
            try await refreshAuthorization(for: request, unauthorized: error)
            let retry = try await buildRequest(endpoint, method: method, body: requestBody)
            return try await perform(retry, endpoint: endpoint)
        }
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        endpoint: APIEndpoint,
    ) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        try lifetime?.check()
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

    private func buildRequest(
        _ endpoint: APIEndpoint,
        method: String,
        body: RequestBody?,
    ) async throws -> URLRequest {
        try lifetime?.check()
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
        if endpoint.requiresAuth {
            let token = await session.currentAccessToken(forAccountId: accountId)
            try lifetime?.check()
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            } else if accountId != nil {
                throw CancellationError()
            }
        }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            do {
                switch body {
                case .encodable(let value):
                    request.httpBody = try encoder.encode(value)
                case .json(let data):
                    request.httpBody = data
                }
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
            code: http.statusCode == 401 ? .unauthorized : .internal_,
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
