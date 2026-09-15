import Foundation

/// Weather + lightweight search adapters per skill §"Friend-level
/// capabilities". Both call the server endpoints (which hold the
/// provider keys); the client only renders results and never speaks to
/// weather/search providers directly.
public actor WeatherCapability {
    public struct WeatherResult: Codable, Sendable, Equatable {
        public let city: String
        public let temperatureC: Double
        public let condition: String
        public let observedAt: Date
        public let source: String
    }

    private let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    public func fetch(city: String) async throws -> WeatherResult {
        struct Body: Codable { let city: String }
        return try await http.send(
            Endpoints.capabilityWeather,
            method: "POST",
            body: Body(city: city),
            as: WeatherResult.self,
        )
    }
}

public actor SearchCapability {
    public struct SearchResult: Codable, Sendable, Equatable {
        public struct Entry: Codable, Sendable, Equatable {
            public let title: String
            public let url: String
            public let snippet: String
            public let retrievedAt: Date
        }
        public let query: String
        public let results: [Entry]
        public let source: String
    }

    private let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    public func fetch(query: String) async throws -> SearchResult {
        struct Body: Codable { let query: String }
        return try await http.send(
            Endpoints.capabilitySearch,
            method: "POST",
            body: Body(query: query),
            as: SearchResult.self,
        )
    }
}