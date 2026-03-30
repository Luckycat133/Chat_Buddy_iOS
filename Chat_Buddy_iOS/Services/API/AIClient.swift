import Foundation

/// Singleton AI client for chat completions, mirroring web's aiClient.js
final class AIClient {
    static let shared = AIClient()

    private var apiClient: APIClient = APIClient(config: .default)
    private var lastConfig: APIConfig = .default
    private static let decoder = JSONDecoder()

    private init() {}

    /// Send a chat completion request using the provided config.
    func sendChatCompletion(
        messages: [ChatMessage],
        model: String? = nil,
        temperature: Double? = nil,
        config: APIConfig
    ) async throws -> ChatCompletionResponse {
        // Reuse the existing actor; only rebuild when the config has changed.
        if config != lastConfig {
            apiClient = APIClient(config: config)
            lastConfig = config
        }

        let request = ChatCompletionRequest(
            model: model ?? config.model,
            messages: messages,
            temperature: temperature ?? config.temperature,
            maxTokens: nil,
            stream: false
        )

        let data = try await apiClient.post("/chat/completions", body: request)

        do {
            return try Self.decoder.decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
