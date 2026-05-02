import Foundation

struct APIConfig: Codable, Equatable {
    var baseURL: String
    var apiKey: String = ""
    var model: String
    var temperature: Double
    var timeout: TimeInterval
    var maxRetries: Int

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

    var isValid: Bool {
        guard !baseURL.isEmpty, !apiKey.isEmpty, !model.isEmpty else { return false }
        guard URL(string: baseURL) != nil else { return false }
        guard baseURL.hasPrefix("http://") || baseURL.hasPrefix("https://") else { return false }
        guard (0.1...2).contains(temperature) else { return false }
        guard timeout > 0 else { return false }
        guard maxRetries >= 0 else { return false }
        return true
    }
}
