import Foundation

// MARK: - Forward-compatible enums with unknown fallback
//
// Per skill §"API models and contract discipline": unknown enum fallback
// where forward compatibility is required. These mirror the server's
// `shared/contracts/enums.ts` (contract 2026-08-18-demo-v1); newer server
// values decode as `.unknown(raw)` instead of failing the whole DTO.

public enum RemoteActorType: Sendable, Equatable {
    case human
    case character
    case unknown(String)

    public init(serverValue: String) {
        switch serverValue {
        case "human": self = .human
        case "character": self = .character
        default: self = .unknown(serverValue)
        }
    }

    /// Raw value for cache storage (unknown values round-trip verbatim).
    public var storedValue: String {
        switch self {
        case .human: return "human"
        case .character: return "character"
        case .unknown(let raw): return raw
        }
    }

    public var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }
}

public enum RemoteConversationType: Sendable, Equatable {
    case direct
    case group
    case hiddenAiDirect
    case unknown(String)

    public init(serverValue: String) {
        switch serverValue {
        case "direct": self = .direct
        case "group": self = .group
        case "hidden_ai_direct": self = .hiddenAiDirect
        default: self = .unknown(serverValue)
        }
    }

    public var storedValue: String {
        switch self {
        case .direct: return "direct"
        case .group: return "group"
        case .hiddenAiDirect: return "hidden_ai_direct"
        case .unknown(let raw): return raw
        }
    }
}

public enum RemoteMessageKind: Sendable, Equatable {
    case text
    case image
    case system
    case invitation
    case actionResult
    case unknown(String)

    public init(serverValue: String) {
        switch serverValue {
        case "text": self = .text
        case "image": self = .image
        case "system": self = .system
        case "invitation": self = .invitation
        case "action_result": self = .actionResult
        default: self = .unknown(serverValue)
        }
    }

    public var storedValue: String {
        switch self {
        case .text: return "text"
        case .image: return "image"
        case .system: return "system"
        case .invitation: return "invitation"
        case .actionResult: return "action_result"
        case .unknown(let raw): return raw
        }
    }
}

/// Server DTOs for the cloud surface consumed by iOS.
///
/// Per skill §"API models and contract discipline":
///   - explicit coding keys
///   - ISO-8601 date strategy with fractional seconds support
///   - unknown enum fallback where forward compatibility is required
///   - no force unwraps for server data
///   - separate from long-lived SwiftUI state (handled in `ActorViewData`)

public struct RemoteActorDTO: Codable, Sendable, Equatable {
    public let id: String
    public let socialGraphId: String
    public let type: String
    public let publicName: String
    public let avatarAssetId: String?
    public let templateId: String?
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, type, publicName, status
        case socialGraphId, avatarAssetId, templateId
    }

    public init(
        id: String,
        socialGraphId: String,
        type: String,
        publicName: String,
        avatarAssetId: String?,
        templateId: String?,
        status: String,
    ) {
        self.id = id
        self.socialGraphId = socialGraphId
        self.type = type
        self.publicName = publicName
        self.avatarAssetId = avatarAssetId
        self.templateId = templateId
        self.status = status
    }

    /// `GET /v1/actors` is a public list projection and intentionally
    /// omits `socialGraphId`; actor detail and sync rows include it.
    /// Treat the omitted list field as unknown rather than failing the
    /// entire contacts refresh. Repositories preserve an already-cached
    /// graph id when this value is empty.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        socialGraphId = try container.decodeIfPresent(String.self, forKey: .socialGraphId) ?? ""
        type = try container.decode(String.self, forKey: .type)
        publicName = try container.decode(String.self, forKey: .publicName)
        avatarAssetId = try container.decodeIfPresent(String.self, forKey: .avatarAssetId)
        templateId = try container.decodeIfPresent(String.self, forKey: .templateId)
        status = try container.decode(String.self, forKey: .status)
    }
}

public struct RemoteConversationDTO: Codable, Sendable, Equatable {
    public let id: String
    public let socialGraphId: String
    public let type: String
    public let publicName: String?
    public let createdByActorId: String
    public let status: String
    public let createdAt: Date

    public init(
        id: String,
        socialGraphId: String,
        type: String,
        publicName: String?,
        createdByActorId: String,
        status: String,
        createdAt: Date,
    ) {
        self.id = id
        self.socialGraphId = socialGraphId
        self.type = type
        self.publicName = publicName
        self.createdByActorId = createdByActorId
        self.status = status
        self.createdAt = createdAt
    }
}

public struct RemoteMessageDTO: Codable, Sendable, Equatable {
    public let id: String
    public let conversationId: String
    public let senderActorId: String
    public let sequence: Int
    public let clientIdempotencyKey: String
    public let kind: String
    /// Typed view of `kind` with unknown-value fallback (contract enums.ts).
    public var messageKind: RemoteMessageKind { RemoteMessageKind(serverValue: kind) }
    public let content: String
    public let structuredPayload: String?
    public let replyToMessageId: String?
    public let burstId: String?
    public let status: String
    public let createdAt: Date
    /// Contract `message.ts` carries `editedAt: ISO | null`.
    public let editedAt: Date?
    public let deletedAt: Date?

    /// Single source of truth for "was this written by a human?".
    ///
    /// Server convention (see CloudClientTests + chat skill): the signed-in
    /// human's actor id carries the reserved all-zero UUID prefix
    /// (`00000000-…`); character actors (Mira/Luna/Max) use ordinary UUIDs.
    /// `senderActorId == conversationId` additionally covers older server
    /// payloads that collapsed the sender into the direct-conversation id.
    /// The former `hasPrefix("user-")` check was dropped: no server payload
    /// uses that prefix and it misclassified every character message.
    public var isFromHuman: Bool {
        senderActorId.hasPrefix("00000000-") || senderActorId == conversationId
    }

    public init(
        id: String,
        conversationId: String,
        senderActorId: String,
        sequence: Int,
        clientIdempotencyKey: String,
        kind: String,
        content: String,
        structuredPayload: String?,
        replyToMessageId: String?,
        burstId: String?,
        status: String,
        createdAt: Date,
        editedAt: Date?,
        deletedAt: Date?,
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderActorId = senderActorId
        self.sequence = sequence
        self.clientIdempotencyKey = clientIdempotencyKey
        self.kind = kind
        self.content = content
        self.structuredPayload = structuredPayload
        self.replyToMessageId = replyToMessageId
        self.burstId = burstId
        self.status = status
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, conversationId, senderActorId, sequence, clientIdempotencyKey
        case kind, content, structuredPayload, replyToMessageId, burstId, status
        case createdAt, editedAt, deletedAt
    }

    /// Custom decode because the server sends `structuredPayload` as
    /// `record(z.unknown()) | null` (contract message.ts), i.e. an actual
    /// JSON object — not a string. Objects are canonicalized to JSON text
    /// for cache storage; strings/null pass through. The former synthesized
    /// decode threw `typeMismatch` on every invitation/action_result
    /// message payload.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        senderActorId = try container.decode(String.self, forKey: .senderActorId)
        sequence = try container.decode(Int.self, forKey: .sequence)
        clientIdempotencyKey = try container.decode(String.self, forKey: .clientIdempotencyKey)
        kind = try container.decode(String.self, forKey: .kind)
        content = try container.decode(String.self, forKey: .content)
        replyToMessageId = try container.decodeIfPresent(String.self, forKey: .replyToMessageId)
        burstId = try container.decodeIfPresent(String.self, forKey: .burstId)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)

        let rawPayload = try container.decodeIfPresent(AnyJSON.self, forKey: .structuredPayload)
        switch rawPayload {
        case .none, .some(.null):
            structuredPayload = nil
        case .some(.string(let text)):
            structuredPayload = text
        case .some(let value):
            let data = try JSONEncoder().encode(value)
            structuredPayload = String(data: data, encoding: .utf8)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(senderActorId, forKey: .senderActorId)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(clientIdempotencyKey, forKey: .clientIdempotencyKey)
        try container.encode(kind, forKey: .kind)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(structuredPayload, forKey: .structuredPayload)
        try container.encodeIfPresent(replyToMessageId, forKey: .replyToMessageId)
        try container.encodeIfPresent(burstId, forKey: .burstId)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(editedAt, forKey: .editedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

public struct RemoteMomentDTO: Codable, Sendable, Equatable {
    public let id: String
    public let actorId: String
    public let socialGraphId: String
    public let content: String
    public let audiencePolicy: String
    public let sourceEventId: String?
    public let createdAt: Date
    public let deletedAt: Date?

    public init(
        id: String,
        actorId: String,
        socialGraphId: String,
        content: String,
        audiencePolicy: String,
        sourceEventId: String?,
        createdAt: Date,
        deletedAt: Date?,
    ) {
        self.id = id
        self.actorId = actorId
        self.socialGraphId = socialGraphId
        self.content = content
        self.audiencePolicy = audiencePolicy
        self.sourceEventId = sourceEventId
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

public struct RemoteFriendRequestDTO: Codable, Sendable, Equatable {
    public let id: String
    public let senderActorId: String
    public let recipientActorId: String
    public let status: String
    public let note: String?
    public let createdAt: Date

    public init(
        id: String,
        senderActorId: String,
        recipientActorId: String,
        status: String,
        note: String?,
        createdAt: Date,
    ) {
        self.id = id
        self.senderActorId = senderActorId
        self.recipientActorId = recipientActorId
        self.status = status
        self.note = note
        self.createdAt = createdAt
    }
}

public struct RemoteRelationshipDTO: Codable, Sendable, Equatable {
    public let id: String
    public let actorAId: String
    public let actorBId: String
    public let state: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        actorAId: String,
        actorBId: String,
        state: String,
        createdAt: Date,
        updatedAt: Date,
    ) {
        self.id = id
        self.actorAId = actorAId
        self.actorBId = actorBId
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RemoteMemoryItemDTO: Codable, Sendable, Equatable {
    public let id: String
    public let ownerActorId: String
    public let relationshipId: String?
    public let type: String
    public let objectiveFact: String
    public let subjectiveInterpretation: String
    public let confidence: String
    public let visibilityPolicy: String
    public let sharePolicy: String
    public let createdAt: Date

    public init(
        id: String,
        ownerActorId: String,
        relationshipId: String?,
        type: String,
        objectiveFact: String,
        subjectiveInterpretation: String,
        confidence: String,
        visibilityPolicy: String,
        sharePolicy: String,
        createdAt: Date,
    ) {
        self.id = id
        self.ownerActorId = ownerActorId
        self.relationshipId = relationshipId
        self.type = type
        self.objectiveFact = objectiveFact
        self.subjectiveInterpretation = subjectiveInterpretation
        self.confidence = confidence
        self.visibilityPolicy = visibilityPolicy
        self.sharePolicy = sharePolicy
        self.createdAt = createdAt
    }
}

public struct RemoteWorldEventDTO: Codable, Sendable, Equatable {
    public let id: String
    public let socialGraphId: String
    public let type: String
    public let actorId: String
    public let occurredAt: Date
    public let visibilityPolicy: String

    public init(
        id: String,
        socialGraphId: String,
        type: String,
        actorId: String,
        occurredAt: Date,
        visibilityPolicy: String,
    ) {
        self.id = id
        self.socialGraphId = socialGraphId
        self.type = type
        self.actorId = actorId
        self.occurredAt = occurredAt
        self.visibilityPolicy = visibilityPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case id, socialGraphId, type, actorId, occurredAt, visibilityPolicy
    }

    /// The server's sync projection stores `visibilityPolicy` as a JSON
    /// object, while the local cache keeps a canonical string. Older
    /// fixtures used a string directly, so accept both representations.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        socialGraphId = try container.decode(String.self, forKey: .socialGraphId)
        type = try container.decode(String.self, forKey: .type)
        actorId = try container.decode(String.self, forKey: .actorId)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)

        let policy = try container.decode(AnyJSON.self, forKey: .visibilityPolicy)
        switch policy {
        case .string(let value):
            visibilityPolicy = value
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(policy)
            visibilityPolicy = String(decoding: data, as: UTF8.self)
        }
    }
}

// MARK: - Conversation membership / bursts / invitations

/// Contract `conversation.ts` member row. Sync upserts key members by
/// `(conversationId, actorId)`; the optional server row id is carried but
/// not used for cache identity.
public struct RemoteConversationMemberDTO: Codable, Sendable, Equatable {
    public let id: String?
    public let conversationId: String
    public let actorId: String
    public let status: String
    public let role: String
    public let invitedByActorId: String?
    public let joinedAt: Date?
    public let leftAt: Date?
    public let lastReadSequence: Int?

    public init(
        id: String?,
        conversationId: String,
        actorId: String,
        status: String,
        role: String,
        invitedByActorId: String?,
        joinedAt: Date?,
        leftAt: Date?,
        lastReadSequence: Int?,
    ) {
        self.id = id
        self.conversationId = conversationId
        self.actorId = actorId
        self.status = status
        self.role = role
        self.invitedByActorId = invitedByActorId
        self.joinedAt = joinedAt
        self.leftAt = leftAt
        self.lastReadSequence = lastReadSequence
    }
}

/// Contract `message.ts` MessageBurst row.
public struct RemoteMessageBurstDTO: Codable, Sendable, Equatable {
    public let id: String
    public let conversationId: String
    public let senderActorId: String
    public let firstMessageSequence: Int
    public let lastMessageSequence: Int
    public let closedReason: String?
    public let openedAt: Date
    public let closedAt: Date?

    public init(
        id: String,
        conversationId: String,
        senderActorId: String,
        firstMessageSequence: Int,
        lastMessageSequence: Int,
        closedReason: String?,
        openedAt: Date,
        closedAt: Date?,
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderActorId = senderActorId
        self.firstMessageSequence = firstMessageSequence
        self.lastMessageSequence = lastMessageSequence
        self.closedReason = closedReason
        self.openedAt = openedAt
        self.closedAt = closedAt
    }
}

/// Contract `social.ts` GroupInvitation row.
public struct RemoteGroupInvitationDTO: Codable, Sendable, Equatable {
    public let id: String
    public let conversationId: String
    public let inviterActorId: String
    public let inviteeActorId: String
    public let purpose: String?
    public let status: String
    public let createdAt: Date
    public let decidedAt: Date?

    public init(
        id: String,
        conversationId: String,
        inviterActorId: String,
        inviteeActorId: String,
        purpose: String?,
        status: String,
        createdAt: Date,
        decidedAt: Date?,
    ) {
        self.id = id
        self.conversationId = conversationId
        self.inviterActorId = inviterActorId
        self.inviteeActorId = inviteeActorId
        self.purpose = purpose
        self.status = status
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }
}