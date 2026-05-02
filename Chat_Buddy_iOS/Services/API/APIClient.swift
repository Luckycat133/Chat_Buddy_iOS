import Foundation
import os.log

actor APIClient {
    private let session: URLSession
    private var baseURL: String
    private var authToken: String?
    private var timeout: TimeInterval
    private var maxRetries: Int

    private static let maxRetryDelay: TimeInterval = 10.0
    private static let encoder = JSONEncoder()
    private static let logger = Logger(subsystem: "com.chatbuddy", category: "APIClient")

    init(config: APIConfig) {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeout
        self.session = URLSession(configuration: sessionConfig)
        self.baseURL = config.baseURL
        self.authToken = config.apiKey.isEmpty ? nil : config.apiKey
        self.timeout = config.timeout
        self.maxRetries = config.maxRetries
    }

    func updateConfig(_ config: APIConfig) {
        self.baseURL = config.baseURL
        self.authToken = config.apiKey.isEmpty ? nil : config.apiKey
        self.timeout = config.timeout
        self.maxRetries = config.maxRetries
    }

    func get(_ endpoint: String) async throws -> Data {
        try await request(endpoint, method: "GET")
    }

    func post(_ endpoint: String, body: some Encodable) async throws -> Data {
        let data = try Self.encoder.encode(body)
        return try await request(endpoint, method: "POST", body: data)
    }

    private func request(
        _ endpoint: String,
        method: String,
        body: Data? = nil,
        retries: Int? = nil
    ) async throws -> Data {
        let url = try buildURL(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body

        return try await fetchWithRetry(request, retriesLeft: retries ?? maxRetries, attempt: 0)
    }

    private func fetchWithRetry(_ request: URLRequest, retriesLeft: Int, attempt: Int) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 429 && retriesLeft > 0 {
                let waitTime = min(
                    Double(maxRetries - retriesLeft + 1) + Double.random(in: 0...0.5),
                    Self.maxRetryDelay
                )
                Self.logger.info("Rate limited (429), retrying in \(waitTime)s...")
                try await Task.sleep(for: .seconds(waitTime))
                return try await fetchWithRetry(request, retriesLeft: retriesLeft - 1, attempt: attempt + 1)
            }

            if httpResponse.statusCode >= 500 && retriesLeft > 0 {
                let waitTime = min(1.0 * Double(maxRetries - retriesLeft + 1), Self.maxRetryDelay)
                Self.logger.info("Server error (\(httpResponse.statusCode)), retrying in \(waitTime)s...")
                try await Task.sleep(for: .seconds(waitTime))
                return try await fetchWithRetry(request, retriesLeft: retriesLeft - 1, attempt: attempt + 1)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.httpError(statusCode: httpResponse.statusCode, body: body)
            }

            return data

        } catch let error as APIError {
            throw error
        } catch {
            if retriesLeft > 0 && !(error is CancellationError) {
                let waitTime = Double(attempt + 1)
                Self.logger.info("Network error, retrying in \(waitTime)s...")
                try await Task.sleep(for: .seconds(waitTime))
                return try await fetchWithRetry(request, retriesLeft: retriesLeft - 1, attempt: attempt + 1)
            }
            throw APIError.networkError(error)
        }
    }

    private func buildURL(_ endpoint: String) throws -> URL {
        if (endpoint.hasPrefix("http://") || endpoint.hasPrefix("https://")),
           let url = URL(string: endpoint) {
            return url
        }
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL(endpoint)
        }
        return url
    }
}

enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case networkError(Error)
    case decodingError(Error)
    case validationError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body.prefix(200))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .validationError(let message):
            return message
        }
    }
}
