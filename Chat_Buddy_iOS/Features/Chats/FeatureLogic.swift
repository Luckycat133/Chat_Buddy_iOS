import Foundation

/// Pure, UI-free feature logic for the cloud Feature layer.
///
/// Kept free of SwiftUI/UIKit so unit tests can exercise it directly
/// (`Chat_Buddy_iOSTests/CloudFeatureTests.swift`).

// MARK: - Chat optimistic rows

/// One renderable chat row. Merges server messages with optimistic local
/// outbox rows so the composer never blocks and failures stay visible.
public struct ChatRowModel: Identifiable, Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case delivered
        case queued
        case sending
        case failed
        case conflict
    }

    public let id: String
    public let conversationId: String
    public let senderActorId: String
    public let content: String
    public let createdAt: Date
    public let isFromHuman: Bool
    public let isLocalOnly: Bool
    public let idempotencyKey: String?
    public let status: Status

    public init(
        id: String,
        conversationId: String,
        senderActorId: String,
        content: String,
        createdAt: Date,
        isFromHuman: Bool,
        isLocalOnly: Bool,
        idempotencyKey: String?,
        status: Status,
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderActorId = senderActorId
        self.content = content
        self.createdAt = createdAt
        self.isFromHuman = isFromHuman
        self.isLocalOnly = isLocalOnly
        self.idempotencyKey = idempotencyKey
        self.status = status
    }

    public static func fromServer(_ dto: RemoteMessageDTO) -> ChatRowModel {
        ChatRowModel(
            id: dto.id,
            conversationId: dto.conversationId,
            senderActorId: dto.senderActorId,
            content: dto.content,
            createdAt: dto.createdAt,
            isFromHuman: dto.isFromHuman,
            isLocalOnly: false,
            idempotencyKey: dto.clientIdempotencyKey,
            status: dto.status == "failed" ? .failed : .delivered,
        )
    }
}

/// Reducer that merges authoritative server messages with pending local
/// outbox mutations. Rules:
///   - server rows win; an optimistic row disappears once the server
///     message carrying the same `clientIdempotencyKey` arrives
///   - failed/conflict outbox rows stay visible with a retry affordance
///   - ordering is by timestamp then local rows last (stable per burst)
public enum ChatOutboxReducer {
    public static func merge(
        server: [RemoteMessageDTO],
        outbox: [OutboxMutationSnapshot],
        now: Date = Date(),
    ) -> [ChatRowModel] {
        var rows = server.map(ChatRowModel.fromServer)
        let deliveredKeys = Set(server.map(\.clientIdempotencyKey))
        for entry in outbox {
            if deliveredKeys.contains(entry.idempotencyKey) { continue }
            let status: ChatRowModel.Status
            switch entry.state {
            case .queued: status = .queued
            case .sending: status = .sending
            case .failed: status = .failed
            case .conflict: status = .conflict
            case .accepted: continue
            }
            rows.append(
                ChatRowModel(
                    id: "local-\(entry.idempotencyKey)",
                    conversationId: entry.conversationId,
                    senderActorId: entry.senderActorId ?? "00000000-local",
                    content: entry.content,
                    createdAt: entry.createdAt,
                    isFromHuman: true,
                    isLocalOnly: true,
                    idempotencyKey: entry.idempotencyKey,
                    status: status,
                ),
            )
        }
        return rows.sorted {
            if $0.createdAt == $1.createdAt {
                // Keep optimistic rows after equal-timestamp server rows.
                return $0.isLocalOnly == false && $1.isLocalOnly == true
            }
            return $0.createdAt < $1.createdAt
        }
    }

    /// Server messages that should replace the local pending row.
    public static func reconciled(
        server: [RemoteMessageDTO],
    ) -> [RemoteMessageDTO] {
        var seen = Set<String>()
        return server.filter { dto in
            // Duplicate realtime/replay protection by idempotency key.
            guard !seen.contains(dto.clientIdempotencyKey) else { return false }
            seen.insert(dto.clientIdempotencyKey)
            return dto.deletedAt == nil
        }
    }
}

/// Lightweight outbox snapshot decoupled from SwiftData models so the
/// reducer and tests do not need a model container.
public struct OutboxMutationSnapshot: Equatable, Sendable {
    public let idempotencyKey: String
    public let conversationId: String
    public let content: String
    public let senderActorId: String?
    public let state: OutboxState
    public let createdAt: Date

    public init(
        idempotencyKey: String,
        conversationId: String,
        content: String,
        senderActorId: String?,
        state: OutboxState,
        createdAt: Date,
    ) {
        self.idempotencyKey = idempotencyKey
        self.conversationId = conversationId
        self.content = content
        self.senderActorId = senderActorId
        self.state = state
        self.createdAt = createdAt
    }
}

/// Mirror of `OutboxStore.State` for pure logic contexts.
public enum OutboxState: String, Equatable, Sendable {
    case queued, sending, accepted, failed, conflict
}

// MARK: - Contacts five-state projection

/// The five request/relationship surfaces required by skill §12:
/// inbound requests, outbound requests, accepted contacts, declined,
/// blocked. Delete ≠ block ≠ account deletion copy lives in the view;
/// this projection only classifies.
public struct ContactsProjection: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: String
        public let actorId: String
        public let actorName: String
        public let isCharacter: Bool
        public let note: String?
        public let decidedAt: Date?

        public init(
            id: String,
            actorId: String,
            actorName: String,
            isCharacter: Bool,
            note: String?,
            decidedAt: Date?,
        ) {
            self.id = id
            self.actorId = actorId
            self.actorName = actorName
            self.isCharacter = isCharacter
            self.note = note
            self.decidedAt = decidedAt
        }
    }

    public let inbound: [Entry]
    public let outbound: [Entry]
    public let acceptedHumans: [Entry]
    public let acceptedCharacters: [Entry]
    public let declined: [Entry]
    public let blocked: [Entry]
    public let groups: [GroupEntry]

    public struct GroupEntry: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let memberCount: Int
        public let status: String

        public init(id: String, name: String, memberCount: Int, status: String) {
            self.id = id
            self.name = name
            self.memberCount = memberCount
            self.status = status
        }
    }

    public init(
        inbound: [Entry],
        outbound: [Entry],
        acceptedHumans: [Entry],
        acceptedCharacters: [Entry],
        declined: [Entry],
        blocked: [Entry],
        groups: [GroupEntry],
    ) {
        self.inbound = inbound
        self.outbound = outbound
        self.acceptedHumans = acceptedHumans
        self.acceptedCharacters = acceptedCharacters
        self.declined = declined
        self.blocked = blocked
        self.groups = groups
    }
}

public enum ContactsClassifier {
    /// Build the five-state projection from cached server rows.
    /// - Parameters:
    ///   - requests: friend requests involving me (either direction).
    ///   - relationships: relationship rows involving me.
    ///   - actors: actor name/type lookups by id.
    ///   - myActorId: the signed-in human's actor id.
    public static func project(
        requests: [CachedFriendRequestSnapshot],
        relationships: [CachedRelationshipSnapshot],
        actors: [String: ActorBrief],
        myActorId: String,
        conversations: [CachedConversationSnapshot],
    ) -> ContactsProjection {
        var inbound: [ContactsProjection.Entry] = []
        var outbound: [ContactsProjection.Entry] = []
        var declined: [ContactsProjection.Entry] = []

        for request in requests {
            let counterpart = request.senderActorId == myActorId
                ? request.recipientActorId
                : request.senderActorId
            let actor = actors[counterpart]
            let entry = ContactsProjection.Entry(
                id: request.id,
                actorId: counterpart,
                actorName: actor?.publicName ?? counterpart,
                isCharacter: actor?.isCharacter ?? false,
                note: request.note,
                decidedAt: request.decidedAt,
            )
            switch request.status {
            case "pending":
                if request.senderActorId == myActorId {
                    outbound.append(entry)
                } else {
                    inbound.append(entry)
                }
            case "declined", "expired":
                declined.append(entry)
            default:
                break
            }
        }

        var acceptedHumans: [ContactsProjection.Entry] = []
        var acceptedCharacters: [ContactsProjection.Entry] = []
        var blocked: [ContactsProjection.Entry] = []
        for relationship in relationships {
            let counterpart = relationship.actorAId == myActorId
                ? relationship.actorBId
                : relationship.actorAId
            let actor = actors[counterpart]
            let entry = ContactsProjection.Entry(
                id: relationship.id,
                actorId: counterpart,
                actorName: actor?.publicName ?? counterpart,
                isCharacter: actor?.isCharacter ?? false,
                note: nil,
                decidedAt: relationship.updatedAt,
            )
            switch relationship.state {
            case "accepted":
                // Role filter after a full `/v1/actors` pull (the server
                // can carry many non-friend human rows): only a known
                // human or character counterpart renders as a friend.
                // Counterparts with no cached role are never displayed.
                switch actor?.isCharacter {
                case .some(true):
                    acceptedCharacters.append(entry)
                case .some(false):
                    acceptedHumans.append(entry)
                case .none:
                    break
                }
            case "blocked":
                // Blocked always stays visible regardless of role: the
                // safety surface must remain actionable.
                blocked.append(entry)
            default:
                break
            }
        }

        let groups = conversations
            .filter { $0.type == "group" && $0.deletedAt == nil }
            .map {
                ContactsProjection.GroupEntry(
                    id: $0.id,
                    name: $0.publicName ?? "",
                    memberCount: $0.memberCount,
                    status: $0.status,
                )
            }
            .sorted { $0.name < $1.name }

        return ContactsProjection(
            inbound: inbound,
            outbound: outbound,
            acceptedHumans: acceptedHumans,
            acceptedCharacters: acceptedCharacters,
            declined: declined,
            blocked: blocked,
            groups: groups,
        )
    }
}

public struct ActorBrief: Equatable, Sendable {
    public let publicName: String
    public let isCharacter: Bool

    public init(publicName: String, isCharacter: Bool) {
        self.publicName = publicName
        self.isCharacter = isCharacter
    }
}

public struct CachedFriendRequestSnapshot: Equatable, Sendable {
    public let id: String
    public let senderActorId: String
    public let recipientActorId: String
    public let status: String
    public let note: String?
    public let decidedAt: Date?

    public init(
        id: String,
        senderActorId: String,
        recipientActorId: String,
        status: String,
        note: String?,
        decidedAt: Date?,
    ) {
        self.id = id
        self.senderActorId = senderActorId
        self.recipientActorId = recipientActorId
        self.status = status
        self.note = note
        self.decidedAt = decidedAt
    }
}

public struct CachedRelationshipSnapshot: Equatable, Sendable {
    public let id: String
    public let actorAId: String
    public let actorBId: String
    public let state: String
    public let updatedAt: Date

    public init(id: String, actorAId: String, actorBId: String, state: String, updatedAt: Date) {
        self.id = id
        self.actorAId = actorAId
        self.actorBId = actorBId
        self.state = state
        self.updatedAt = updatedAt
    }
}

public struct CachedConversationSnapshot: Equatable, Sendable {
    public let id: String
    public let type: String
    public let publicName: String?
    public let status: String
    public let memberCount: Int
    public let deletedAt: Date?

    public init(
        id: String,
        type: String,
        publicName: String?,
        status: String,
        memberCount: Int,
        deletedAt: Date?,
    ) {
        self.id = id
        self.type = type
        self.publicName = publicName
        self.status = status
        self.memberCount = memberCount
        self.deletedAt = deletedAt
    }
}

// MARK: - Onboarding resume gate

/// Server-driven onboarding state machine. The UI never decides when
/// onboarding is complete — it follows `/v1/onboarding` state.
public enum OnboardingGate {
    public enum ServerState: Equatable, Sendable {
        case notStarted
        case inProgress(step: Int?, awaitingUser: Bool)
        case complete
        case unknown

        public static func parse(_ raw: String, step: Int?, awaitingUser: Bool?) -> ServerState {
            switch raw {
            case "complete", "completed":
                return .complete
            case "in_progress", "active":
                return .inProgress(step: step, awaitingUser: awaitingUser ?? false)
            case "not_started", "pending":
                return .notStarted
            default:
                return .unknown
            }
        }
    }

    /// Whether the app should re-enter the Mira conversation instead of
    /// going straight to Chats. This is the "forkable breakpoint" resume:
    /// leaving mid-onboarding keeps server state, and the next launch
    /// resumes the same conversation.
    public static func shouldResumeOnboarding(_ state: ServerState) -> Bool {
        switch state {
        case .notStarted, .inProgress, .unknown:
            return true
        case .complete:
            return false
        }
    }

    /// Server-owned onboarding states accepted by
    /// `POST /v1/onboarding/advance`. `complete` must never be posted by
    /// the client; unknown future states are left for a newer client.
    public static func advanceTarget(serverValue: String) -> String? {
        switch serverValue {
        case "not_started":
            return "welcome"
        case "welcome", "learn_name", "learn_need", "learn_quiet_hours",
             "learn_social_preference", "learn_open_thread",
             "recommend_characters", "friend_requests", "propose_group",
             "introduce_moments":
            return serverValue
        default:
            return nil
        }
    }
}

// MARK: - Moments

/// Audience badge mapping per skill §15: visible audience indicator.
public enum AudienceBadge {
    public static func key(forClass policyClass: String?) -> String {
        switch policyClass {
        case "public_within_graph": return "cloud_moments_audience_public"
        case "restricted": return "cloud_moments_audience_private"
        default: return "cloud_moments_audience_familiar"
        }
    }

    public static func symbol(forClass policyClass: String?) -> String {
        switch policyClass {
        case "public_within_graph": return "globe"
        case "restricted": return "lock"
        default: return "person.2"
        }
    }
}

/// Pending interaction rows for optimistic reaction/comment rendering.
public struct MomentPendingInteraction: Identifiable, Equatable, Sendable {
    public let id: String
    public let momentId: String
    public let type: String
    public let content: String?
    public let state: OutboxState

    public init(id: String, momentId: String, type: String, content: String?, state: OutboxState) {
        self.id = id
        self.momentId = momentId
        self.type = type
        self.content = content
        self.state = state
    }
}

// MARK: - Group creation wizard

/// Six-step group wizard state per skill §13:
/// 1 name/purpose → 2 select actors → 3 review → 4 send proposal →
/// 5 pending decisions → 6 open group.
public struct GroupWizardState: Equatable, Sendable {
    public enum Step: Int, Equatable, Sendable, CaseIterable {
        case name = 1
        case select = 2
        case review = 3
        case send = 4
        case pending = 5
        case open = 6
    }

    public var step: Step
    public var name: String
    public var purpose: String
    public var selectedActorIds: Set<String>
    public var sentConversationId: String?
    public var proposalError: String?

    public init(
        step: Step = .name,
        name: String = "",
        purpose: String = "",
        selectedActorIds: Set<String> = [],
        sentConversationId: String? = nil,
        proposalError: String? = nil,
    ) {
        self.step = step
        self.name = name
        self.purpose = purpose
        self.selectedActorIds = selectedActorIds
        self.sentConversationId = sentConversationId
        self.proposalError = proposalError
    }

    public var canProceedFromName: Bool { true } // name is optional per skill

    public var canSendProposal: Bool {
        !selectedActorIds.isEmpty
    }

    public func next() -> GroupWizardState {
        var copy = self
        switch step {
        case .name: copy.step = .select
        case .select: copy.step = .review
        case .review: copy.step = .send
        case .send, .pending, .open: break
        }
        return copy
    }

    public func back() -> GroupWizardState {
        var copy = self
        switch step {
        case .select: copy.step = .name
        case .review: copy.step = .select
        case .send: copy.step = .review
        case .name, .pending, .open: break
        }
        return copy
    }
}

/// Natural invitation status line — never exposes model decision metadata.
public enum InvitationStatusCopy {
    public static func key(forStatus status: String) -> String {
        switch status {
        case "accepted": return "cloud_group_invite_accepted"
        case "declined": return "cloud_group_invite_declined"
        case "pending", "invited": return "cloud_group_invite_pending"
        case "left": return "cloud_group_invite_left"
        default: return "cloud_group_invite_pending"
        }
    }
}

// MARK: - Legacy import payload

/// Builds the one-time normalized legacy import batch. Per skill §17:
/// never uploads stored API credentials, never uploads hidden AI
/// transcripts — only user-visible history.
public enum LegacyImportPayloadBuilder {
    /// UserDefaults keys that must never appear in an import payload.
    public static let credentialKeyMarkers = [
        "apiConfig",
        "apiProfiles",
        "apiKey",
        "provider",
        " baseURL", // defensive: never serialize base URLs either
    ]

    public struct Batch: Equatable, Sendable {
        public let conversations: [[String: String]]
        public let moments: [[String: String]]
        public let memories: [[String: String]]
        public let contacts: [[String: String]]

        public var isEmpty: Bool {
            conversations.isEmpty && moments.isEmpty && memories.isEmpty && contacts.isEmpty
        }
    }

    /// Decode legacy `chat-buddy:` JSON payloads into the normalized batch.
    /// Entries whose keys look like credential storage are dropped.
    public static func build(
        chatSessionsData: Data?,
        momentsData: Data?,
        memoriesData: Data?,
        contactsData: Data?,
    ) -> Batch {
        Batch(
            conversations: sanitized(rows(chatSessionsData)),
            moments: sanitized(rows(momentsData)),
            memories: sanitized(rows(memoriesData)),
            contacts: sanitized(rows(contactsData)),
        )
    }

    /// Extract dictionary rows from a legacy JSON payload. Legacy storage
    /// persisted either a bare array of codables or a wrapper object whose
    /// member is an array; both shapes collapse into dict rows.
    static func rows(_ data: Data?) -> [[String: String]] {
        guard let data else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = object as? [[String: Any]] {
            return array.compactMap(Self.row)
        }
        if let wrapper = object as? [String: Any] {
            for value in wrapper.values {
                if let array = value as? [[String: Any]] {
                    return array.compactMap(Self.row)
                }
            }
            if let single = Self.row(wrapper) { return [single] }
        }
        return []
    }

    private static func row(_ object: Any) -> [String: String]? {
        guard let dict = object as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, value) in dict {
            switch value {
            case let v as String: result[key] = v
            case let v as NSNumber: result[key] = v.stringValue
            case let v as Bool: result[key] = v ? "true" : "false"
            case is NSNull: break
            default: result[key] = "\(value)"
            }
        }
        return result
    }

    /// Drop any row containing a credential-looking key.
    public static func sanitized(
        _ rows: [[String: String]],
    ) -> [[String: String]] {
        rows.filter { row in
            !row.keys.contains { key in
                credentialKeyMarkers.contains { marker in
                    key.lowercased().contains(marker.lowercased())
                }
            }
        }
    }
}
