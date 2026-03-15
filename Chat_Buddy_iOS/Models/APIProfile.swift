import Foundation

/// A saved API configuration profile (e.g. "OpenAI", "DeepSeek", "Perplexity")
struct APIProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var config: APIConfig
    var createdAt: Date

    init(name: String, config: APIConfig) {
        self.id = UUID()
        self.name = name
        self.config = config
        self.createdAt = Date()
    }
}
