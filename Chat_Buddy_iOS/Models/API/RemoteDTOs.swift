import Foundation

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
    public let content: String
    public let structuredPayload: String?
    public let replyToMessageId: String?
    public let burstId: String?
    public let status: String
    public let createdAt: Date
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
        self.deletedAt = deletedAt
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
}