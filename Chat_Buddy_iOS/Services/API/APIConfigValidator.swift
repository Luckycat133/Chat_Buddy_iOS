import Foundation

struct APIConfigValidator {
    static func testConnection(config: APIConfig) async -> Result<Int, Error> {
        guard config.isValid else {
            return .failure(APIError.validationError("Missing required fields or invalid configuration"))
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let messages = [
                APIMessage(role: "user", content: "Hi")
            ]

            let request = ChatCompletionRequest(
                model: config.model,
                messages: messages,
                temperature: config.temperature,
                maxTokens: nil,
                stream: false
            )

            let client = APIClient(config: config)
            _ = try await client.post("/chat/completions", body: request)

            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            return .success(elapsed)
        } catch {
            return .failure(error)
        }
    }
}
