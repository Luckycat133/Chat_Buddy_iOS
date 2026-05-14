import Foundation
import os.log

actor AIClient {
    static let shared = AIClient()

    private var apiClient: APIClient
    private var lastConfig: APIConfig = .default
    private let decoder: JSONDecoder
    private static let logger = Logger(subsystem: "com.chatbuddy", category: "AIClient")

    private init() {
        self.apiClient = APIClient(config: .default)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    func sendChatCompletion(
        messages: [ChatMessage],
        model: String? = nil,
        temperature: Double? = nil,
        config: APIConfig
    ) async throws -> ChatCompletionResponse {
        if config != lastConfig {
            apiClient = APIClient(config: config)
            lastConfig = config
        }

        let apiMessages = messages.map { APIMessage(from: $0) }
        let request = ChatCompletionRequest(
            model: model ?? config.model,
            messages: apiMessages,
            temperature: temperature ?? config.temperature,
            maxTokens: nil,
            stream: false
        )

        let data = try await apiClient.post("/chat/completions", body: request)

        do {
            return try decode(ChatCompletionResponse.self, from: data)
        } catch {
            Self.logger.error("Decoding error: \(error.localizedDescription)")
            throw APIError.decodingError(error)
        }
    }
}
