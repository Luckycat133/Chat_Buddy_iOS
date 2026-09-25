import Foundation

/// View-layer projection per skill §"API models and contract discipline":
///
///   Remote DTO (transport)  →  Cached model (SwiftData)  →  ViewData (SwiftUI)
///
/// Network DTOs must never become long-lived SwiftUI state, and cached
/// rows must not be exposed raw to views (they carry transport fields and
/// server-only semantics). These structs are `Hashable`, `Sendable`, and
/// cheap to build so stores can publish arrays of them.
public struct ActorViewData: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let avatarAssetId: String?
    public let templateId: String?
    public let actorType: RemoteActorType
    public let isCharacter: Bool
    public let status: String

    public init(cached: CachedActor) {
        self.id = cached.id
        self.displayName = cached.publicName
        self.avatarAssetId = cached.avatarAssetId
        self.templateId = cached.templateId
        // Unknown server types round-trip; only `character` renders as one.
        self.actorType = RemoteActorType(serverValue: cached.type)
        self.isCharacter = actorType.isCharacter
        self.status = cached.status
    }
}

public struct ConversationViewData: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String?
    public let conversationType: RemoteConversationType
    public let isGroup: Bool
    public let isHiddenAiDirect: Bool
    public let status: String

    public init(cached: CachedConversation) {
        self.id = cached.id
        self.title = cached.publicName
        self.conversationType = RemoteConversationType(serverValue: cached.type)
        if case .group = conversationType {
            self.isGroup = true
        } else {
            self.isGroup = false
        }
        if case .hiddenAiDirect = conversationType {
            self.isHiddenAiDirect = true
        } else {
            self.isHiddenAiDirect = false
        }
        self.status = cached.status
    }
}

public struct MessageViewData: Identifiable, Hashable, Sendable {
    public let id: String
    public let conversationId: String
    public let text: String
    public let kind: RemoteMessageKind
    public let isFromHuman: Bool
    public let sentAt: Date
    public let editedAt: Date?
    public let isDeleted: Bool
    public let status: String
    public let burstId: String?

    public init(cached: CachedMessage) {
        self.id = cached.id
        self.conversationId = cached.conversationId
        self.text = cached.deletedAt == nil ? cached.content : ""
        self.kind = RemoteMessageKind(serverValue: cached.kind)
        self.isFromHuman = cached.senderActorId.hasPrefix("00000000-")
            || cached.senderActorId == cached.conversationId
        self.sentAt = cached.createdAt
        self.editedAt = cached.editedAt
        self.isDeleted = cached.deletedAt != nil
        self.status = cached.status
        self.burstId = cached.burstId
    }
}

public struct MomentViewData: Identifiable, Hashable, Sendable {
    public let id: String
    public let actorId: String
    public let text: String
    public let audiencePolicy: String
    public let createdAt: Date
    public let isDeleted: Bool

    public init(cached: CachedMoment) {
        self.id = cached.id
        self.actorId = cached.actorId
        self.text = cached.deletedAt == nil ? cached.content : ""
        self.audiencePolicy = cached.audiencePolicy
        self.createdAt = cached.createdAt
        self.isDeleted = cached.deletedAt != nil
    }
}

public struct FriendRequestViewData: Identifiable, Hashable, Sendable {
    public let id: String
    public let senderActorId: String
    public let recipientActorId: String
    public let status: String
    public let note: String?
    public let createdAt: Date

    public init(cached: CachedFriendRequest) {
        self.id = cached.id
        self.senderActorId = cached.senderActorId
        self.recipientActorId = cached.recipientActorId
        self.status = cached.status
        self.note = cached.note
        self.createdAt = cached.createdAt
    }
}

public struct GroupInvitationViewData: Identifiable, Hashable, Sendable {
    public let id: String
    public let conversationId: String
    public let inviterActorId: String
    public let inviteeActorId: String
    public let purpose: String
    public let status: String
    public let decidedAt: Date?

    public init(cached: CachedGroupInvitation) {
        self.id = cached.id
        self.conversationId = cached.conversationId
        self.inviterActorId = cached.inviterActorId
        self.inviteeActorId = cached.inviteeActorId
        self.purpose = cached.purpose
        self.status = cached.status
        self.decidedAt = cached.decidedAt
    }
}
