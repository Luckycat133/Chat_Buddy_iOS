import Foundation

/// A saved chat message the user has bookmarked for later reference
struct Bookmark: Identifiable, Codable {
    var id: String
    var messageId: String
    var sessionId: String
    var content: String
    var personaId: String
    var bookmarkedAt: Date

    init(messageId: String, sessionId: String, content: String, personaId: String) {
        self.id = UUID().uuidString
        self.messageId = messageId
        self.sessionId = sessionId
        self.content = content
        self.personaId = personaId
        self.bookmarkedAt = Date()
    }
}
