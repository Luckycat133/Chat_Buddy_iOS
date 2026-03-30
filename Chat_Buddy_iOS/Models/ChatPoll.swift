import Foundation

struct ChatPollOption: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var votes: [String]

    init(id: String = UUID().uuidString, text: String, votes: [String] = []) {
        self.id = id
        self.text = text
        self.votes = votes
    }
}

struct ChatPoll: Identifiable, Codable, Equatable {
    var id: String
    var question: String
    var options: [ChatPollOption]
    var allowsMultipleSelection: Bool
    var isAnonymous: Bool
    var expiresAt: Date?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        question: String,
        options: [ChatPollOption],
        allowsMultipleSelection: Bool = false,
        isAnonymous: Bool = false,
        expiresAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.allowsMultipleSelection = allowsMultipleSelection
        self.isAnonymous = isAnonymous
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    var isExpired: Bool {
        if let expiresAt {
            return Date() >= expiresAt
        }
        return false
    }
}

struct ChatPermissions: Codable, Equatable {
    var allowReactions: Bool
    var allowImages: Bool

    static let `default` = ChatPermissions(allowReactions: true, allowImages: false)
}

struct GroupAnnouncement: Codable, Equatable {
    var content: String
    var updatedAt: Date
    var createdBy: String

    init(content: String, updatedAt: Date = Date(), createdBy: String = "user-me") {
        self.content = content
        self.updatedAt = updatedAt
        self.createdBy = createdBy
    }
}
