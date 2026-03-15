import Foundation

/// Validates API connectivity by sending a test request
struct APIConfigValidator {
    /// Test the connection and return latency in milliseconds
    static func testConnection(config: APIConfig) async -> Result<Int, Error> {
        guard config.isValid else {
            return .failure(APIError.invalidURL("Missing required fields"))
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let messages = [
                ChatMessage(role: .user, content: "Hi")
            ]

            _ = try await AIClient.shared.sendChatCompletion(
                messages: messages,
                config: config
            )

            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            return .success(elapsed)
        } catch {
            return .failure(error)
        }
    }
}
