import Foundation

/// A persistent chat conversation with one or more AI personas.
/// - Single persona (1v1): `personaIds` contains exactly one entry.
/// - Group chat: `personaIds` contains two or more entries.
///
/// **Migration:** Old sessions stored a `personaId: String` key.
/// The custom decoder below reads both old and new formats seamlessly.
struct ChatSession: Identifiable, Codable {
    var id: String
    /// All participating persona IDs. Guaranteed non-empty.
    var personaIds: [String]
    /// Optional display name for group chats; nil for 1v1 sessions.
    var groupName: String?
    var messages: [ChatMessage]
    var polls: [ChatPoll]
    var announcement: GroupAnnouncement?
    var permissions: ChatPermissions
    var isMuted: Bool
    var adminOnly: Bool
    var nicknames: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    // MARK: - Convenience

    /// True when more than one persona participates.
    var isGroup: Bool { personaIds.count > 1 }

    /// First (primary) persona — used for 1v1 views and fallbacks.
    var primaryPersonaId: String { personaIds[0] }

    /// The `personaId` of the first persona — legacy alias kept for call-sites
    /// that haven't yet been updated to `personaIds`.
    @available(*, deprecated, renamed: "primaryPersonaId")
    var personaId: String { primaryPersonaId }

    /// Last non-system message, used for chat list preview.
    var lastMessage: ChatMessage? {
        messages.last(where: { $0.role != .system && $0.role != .tool })
    }

    /// Messages to display in the UI (excludes system and tool-only prompts).
    var displayMessages: [ChatMessage] {
        messages.filter { $0.role != .system && $0.role != .tool }
    }

    // MARK: - Initializers

    /// Create a new 1v1 session.
    init(personaId: String) {
        self.id = UUID().uuidString
        self.personaIds = [personaId]
        self.groupName = nil
        self.messages = []
        self.polls = []
        self.announcement = nil
        self.permissions = .default
        self.isMuted = false
        self.adminOnly = false
        self.nicknames = [:]
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = false
    }

    /// Create a new group session.
    init(personaIds: [String], groupName: String? = nil) {
        precondition(!personaIds.isEmpty, "ChatSession must have at least one persona")
        self.id = UUID().uuidString
        self.personaIds = personaIds
        self.groupName = groupName
        self.messages = []
        self.polls = []
        self.announcement = nil
        self.permissions = .default
        self.isMuted = false
        self.adminOnly = false
        self.nicknames = [:]
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = false
    }

    // MARK: - Codable (forward & backward compatible)

    enum CodingKeys: String, CodingKey {
        case id, personaIds, personaId, groupName, messages, polls
        case announcement, permissions, isMuted, adminOnly, nicknames
        case createdAt, updatedAt, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id        = try container.decode(String.self, forKey: .id)
        messages  = try container.decode([ChatMessage].self, forKey: .messages)
        polls = (try? container.decode([ChatPoll].self, forKey: .polls)) ?? []
        announcement = try? container.decode(GroupAnnouncement.self, forKey: .announcement)
        permissions = (try? container.decode(ChatPermissions.self, forKey: .permissions)) ?? .default
        isMuted = (try? container.decode(Bool.self, forKey: .isMuted)) ?? false
        adminOnly = (try? container.decode(Bool.self, forKey: .adminOnly)) ?? false
        nicknames = (try? container.decode([String: String].self, forKey: .nicknames)) ?? [:]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isPinned  = (try? container.decode(Bool.self, forKey: .isPinned)) ?? false
        groupName = try? container.decode(String.self, forKey: .groupName)

        // Migration: prefer new `personaIds` array; fall back to legacy `personaId` string.
        if let ids = try? container.decode([String].self, forKey: .personaIds), !ids.isEmpty {
            personaIds = ids
        } else if let single = try? container.decode(String.self, forKey: .personaId) {
            personaIds = [single]
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .personaIds,
                in: container,
                debugDescription: "ChatSession missing personaIds or personaId"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(personaIds, forKey: .personaIds)    // always write new format
        try container.encodeIfPresent(groupName, forKey: .groupName)
        try container.encode(messages, forKey: .messages)
        try container.encode(polls, forKey: .polls)
        try container.encodeIfPresent(announcement, forKey: .announcement)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(adminOnly, forKey: .adminOnly)
        try container.encode(nicknames, forKey: .nicknames)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isPinned, forKey: .isPinned)
    }
}
