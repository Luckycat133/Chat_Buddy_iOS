import Foundation

/// Configuration for the API client, matching web's apiConfig system
struct APIConfig: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var model: String
    var temperature: Double
    var timeout: TimeInterval
    var maxRetries: Int

    static let `default` = APIConfig(
        baseURL: "https://api.deepseek.com/v1",
        apiKey: "",
        model: "deepseek-chat",
        temperature: 0.7,
        timeout: 60,
        maxRetries: 3
    )

    /// Whether the config has the minimum fields filled
    var isValid: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
}
