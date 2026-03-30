import Foundation

/// Configuration for the API client, matching web's apiConfig system
struct APIConfig: Codable, Equatable {
    var baseURL: String
    /// API key is stored in the Keychain and is never serialised to disk.
    /// `APIConfigStore` is responsible for populating this field at runtime.
    var apiKey: String = ""
    var model: String
    var temperature: Double
    var timeout: TimeInterval
    var maxRetries: Int

    /// Coding keys intentionally omit `apiKey` so it is never written to
    /// UserDefaults or exported backup files.
    enum CodingKeys: String, CodingKey {
        case baseURL, model, temperature, timeout, maxRetries
    }

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
