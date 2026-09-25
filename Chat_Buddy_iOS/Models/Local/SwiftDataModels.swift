import Foundation
import SwiftData

/// SwiftData cache models per skill §"Replace local authority with cache".
///
/// SwiftData replaces the UserDefaults arrays used by the legacy
/// `ChatStore`/`MomentsStore`. Migrations must remain additive: never
/// wholesale overwrite from a stale snapshot, never delete authoritative
/// rows on a sync gap.
@Model
public final class CachedActor {
    @Attribute(.unique) public var id: String
    public var socialGraphId: String
    public var type: String
    public var publicName: String
    public var avatarAssetId: String?
    public var templateId: String?
    public var status: String
    public var updatedAt: Date

    public init(
        id: String,
        socialGraphId: String,
        type: String,
        publicName: String,
        avatarAssetId: String?,
        templateId: String?,
        status: String,
        updatedAt: Date,
    ) {
        self.id = id
        self.socialGraphId = socialGraphId
        self.type = type
        self.publicName = publicName
        self.avatarAssetId = avatarAssetId
        self.templateId = templateId
        self.status = status
        self.updatedAt = updatedAt
    }
}

@Model
public final class CachedConversation {
    @Attribute(.unique) public var id: String
    public var socialGraphId: String
    public var type: String
    public var publicName: String?
    public var createdByActorId: String
    public var status: String
    public var createdAt: Date

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

@Model
public final class CachedConversationMember {
    public var conversationId: String
    public var actorId: String
    public var status: String
    public var role: String
    public var invitedByActorId: String?
    public var joinedAt: Date?
    public var leftAt: Date?
    public var lastReadSequence: Int

    public init(
        conversationId: String,
        actorId: String,
        status: String,
        role: String,
        invitedByActorId: String?,
        joinedAt: Date?,
        leftAt: Date?,
        lastReadSequence: Int,
    ) {
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

@Model
public final class CachedMessage {
    @Attribute(.unique) public var id: String
    public var conversationId: String
    public var senderActorId: String
    public var sequence: Int
    public var clientIdempotencyKey: String
    public var kind: String
    public var content: String
    public var structuredPayload: String?
    public var replyToMessageId: String?
    public var burstId: String?
    public var status: String
    public var createdAt: Date
    /// Server-side edit timestamp (contract message.ts `editedAt`).
    /// Additive field: SwiftData lightweight migration fills `nil` for
    /// existing rows.
    public var editedAt: Date?
    public var deletedAt: Date?

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
        editedAt: Date? = nil,
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
}

@Model
public final class CachedMessageBurst {
    @Attribute(.unique) public var id: String
    public var conversationId: String
    public var senderActorId: String
    public var firstMessageSequence: Int
    public var lastMessageSequence: Int
    public var closedReason: String?
    public var openedAt: Date
    public var closedAt: Date?

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

@Model
public final class CachedMoment {
    @Attribute(.unique) public var id: String
    public var actorId: String
    public var socialGraphId: String
    public var content: String
    public var audiencePolicy: String
    public var sourceEventId: String?
    public var createdAt: Date
    public var deletedAt: Date?

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

@Model
public final class CachedMomentInteraction {
    @Attribute(.unique) public var id: String
    public var momentId: String
    public var actorId: String
    public var type: String
    public var content: String?
    public var parentInteractionId: String?
    public var createdAt: Date

    public init(
        id: String,
        momentId: String,
        actorId: String,
        type: String,
        content: String?,
        parentInteractionId: String?,
        createdAt: Date,
    ) {
        self.id = id
        self.momentId = momentId
        self.actorId = actorId
        self.type = type
        self.content = content
        self.parentInteractionId = parentInteractionId
        self.createdAt = createdAt
    }
}

@Model
public final class CachedFriendRequest {
    @Attribute(.unique) public var id: String
    public var senderActorId: String
    public var recipientActorId: String
    public var status: String
    public var note: String?
    public var createdAt: Date

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

@Model
public final class CachedRelationship {
    @Attribute(.unique) public var id: String
    public var actorAId: String
    public var actorBId: String
    public var state: String
    public var createdAt: Date
    public var updatedAt: Date

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

@Model
public final class CachedGroupInvitation {
    @Attribute(.unique) public var id: String
    public var conversationId: String
    public var inviterActorId: String
    public var inviteeActorId: String
    public var purpose: String
    public var status: String
    public var createdAt: Date
    public var decidedAt: Date?

    public init(
        id: String,
        conversationId: String,
        inviterActorId: String,
        inviteeActorId: String,
        purpose: String,
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

@Model
public final class CachedMemoryItem {
    @Attribute(.unique) public var id: String
    public var ownerActorId: String
    public var relationshipId: String?
    public var type: String
    public var objectiveFact: String
    public var subjectiveInterpretation: String
    public var confidence: String
    public var visibilityPolicy: String
    public var sharePolicy: String
    public var createdAt: Date

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

@Model
public final class CachedWorldEvent {
    @Attribute(.unique) public var id: String
    public var socialGraphId: String
    public var type: String
    public var actorId: String
    public var occurredAt: Date
    public var visibilityPolicy: String
    public var deletedAt: Date?

    public init(
        id: String,
        socialGraphId: String,
        type: String,
        actorId: String,
        occurredAt: Date,
        visibilityPolicy: String,
        deletedAt: Date?,
    ) {
        self.id = id
        self.socialGraphId = socialGraphId
        self.type = type
        self.actorId = actorId
        self.occurredAt = occurredAt
        self.visibilityPolicy = visibilityPolicy
        self.deletedAt = deletedAt
    }
}

/// Tombstone for any cached row removed on the server side. Prevents a
/// stale row from re-appearing after reconnect.
@Model
public final class CachedTombstone {
    @Attribute(.unique) public var table: String
    public var rowId: String
    public var deletedAt: Date

    public init(table: String, rowId: String, deletedAt: Date) {
        self.table = table
        self.rowId = rowId
        self.deletedAt = deletedAt
    }
}

/// Sync cursor. Persisted across launches so resume picks up where we left off.
@Model
public final class CachedSyncCursor {
    @Attribute(.unique) public var accountId: String
    public var cursor: String
    public var updatedAt: Date

    public init(accountId: String, cursor: String, updatedAt: Date) {
        self.accountId = accountId
        self.cursor = cursor
        self.updatedAt = updatedAt
    }
}

/// Outbox mutation. Persisted until the server confirms; flushed on
/// reconnect; never dropped without an authoritative result.
@Model
public final class OutboxMutation {
    @Attribute(.unique) public var id: String
    public var accountId: String
    public var idempotencyKey: String
    public var method: String
    public var path: String
    public var bodyData: Data
    public var state: String
    public var attempts: Int
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        accountId: String,
        idempotencyKey: String,
        method: String,
        path: String,
        bodyData: Data,
        state: String,
        attempts: Int,
        lastError: String?,
        createdAt: Date,
        updatedAt: Date,
    ) {
        self.id = id
        self.accountId = accountId
        self.idempotencyKey = idempotencyKey
        self.method = method
        self.path = path
        self.bodyData = bodyData
        self.state = state
        self.attempts = attempts
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
/// Device-local settings per skill §"Replace local authority with cache":
/// small non-sensitive preferences live in SwiftData (NOT full legacy
/// message/moment arrays — those are forbidden in cloud mode). Keychain
/// keeps session secrets; UserDefaults keeps nothing authoritative here.
@Model
public final class CachedDeviceSetting {
    @Attribute(.unique) public var key: String
    public var value: String
    public var updatedAt: Date

    public init(key: String, value: String, updatedAt: Date) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}
