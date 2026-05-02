import Foundation

struct ChatPollOption: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var voterIds: Set<String>

    init(id: String = UUID().uuidString, text: String, voterIds: Set<String> = []) {
        self.id = id
        self.text = text
        self.voterIds = voterIds
    }

    enum CodingKeys: String, CodingKey {
        case id, text
        case voterIds = "votes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        let votesArray = (try? container.decode([String].self, forKey: .voterIds)) ?? []
        voterIds = Set(votesArray)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(Array(voterIds), forKey: .voterIds)
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

    func hasVoted(userId: String) -> Bool {
        options.contains { $0.voterIds.contains(userId) }
    }

    mutating func vote(userId: String, optionIndex: Int) -> Bool {
        guard optionIndex >= 0 && optionIndex < options.count else { return false }
        if !allowsMultipleSelection && hasVoted(userId: userId) { return false }
        if options[optionIndex].voterIds.contains(userId) { return false }
        options[optionIndex].voterIds.insert(userId)
        return true
    }
}
