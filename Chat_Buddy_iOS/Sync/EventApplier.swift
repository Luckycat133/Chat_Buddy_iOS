import Foundation
import SwiftData
import os

/// Applies an ordered delta-sync envelope to the SwiftData cache in one
/// transaction per skill §"Sync coordinator" + IOS_IMPLEMENTATION §10:
///   - upsert by server id (idempotent — re-apply is a no-op)
///   - apply tombstones: delete the row AND record the tombstone
///   - unknown tables are skipped (forward compatible)
///   - pending outbox mutations are preserved (ConflictResolver)
///   - never replaces the whole local store from a stale snapshot
///
/// Extracted from `SyncCoordinator` so the applier is independently
/// testable and SyncCoordinator only owns transport + cursor movement.
public enum EventApplier {

    public struct ApplyResult: Sendable, Equatable {
        /// Client idempotency keys of applied message upserts that matched
        /// pending outbox mutations — the caller reconciles those outbox
        /// rows to `accepted` (idempotency-key reconciliation, §10).
        public let reconciledIdempotencyKeys: Set<String>
        /// Tables that arrived in the envelope but have no client mapping.
        public let skippedTables: Set<String>
    }

    private static let logger = CloudLogger.sync

    public static func apply(
        envelope: SyncCoordinator.ServerEnvelope,
        in context: ModelContext,
        pendingIdempotencyKeys: Set<String> = [],
    ) throws -> ApplyResult {
        var reconciled: Set<String> = []
        var skipped: Set<String> = []

        for upsert in envelope.upserts {
            switch upsert.table {
            case "actors":
                try upsertActor(upsert, in: context)
            case "conversations":
                try upsertConversation(upsert, in: context)
            case "conversation_members":
                try upsertConversationMember(upsert, in: context)
            case "messages":
                let dto = try decode(RemoteMessageDTO.self, upsert: upsert)
                let decision = ConflictResolver.resolveUpsert(
                    messageClientIdempotencyKey: dto.clientIdempotencyKey,
                    pendingIdempotencyKeys: pendingIdempotencyKeys,
                )
                try upsertMessage(dto, id: upsert.id, in: context)
                if case .applyServerAndReconcileOutbox(let key) = decision {
                    reconciled.insert(key)
                }
            case "message_bursts":
                try upsertMessageBurst(upsert, in: context)
            case "moments":
                try upsertMoment(upsert, in: context)
            case "moment_interactions":
                try upsertMomentInteraction(upsert, in: context)
            case "friend_requests":
                try upsertFriendRequest(upsert, in: context)
            case "relationships":
                try upsertRelationship(upsert, in: context)
            case "group_invitations":
                try upsertGroupInvitation(upsert, in: context)
            case "memory_items":
                try upsertMemoryItem(upsert, in: context)
            case "world_events":
                try upsertWorldEvent(upsert, in: context)
            default:
                skipped.insert(upsert.table)
            }
        }

        for tomb in envelope.tombstones {
            try applyTombstone(
                table: tomb.table,
                rowId: tomb.id,
                deletedAt: tomb.deletedAt,
                in: context,
                pendingIdempotencyKeys: pendingIdempotencyKeys,
            )
        }

        try context.save()
        return ApplyResult(reconciledIdempotencyKeys: reconciled, skippedTables: skipped)
    }

    // MARK: - Tombstones

    private static func applyTombstone(
        table: String,
        rowId: String,
        deletedAt: Date,
        in context: ModelContext,
        pendingIdempotencyKeys: Set<String>,
    ) throws {
        var hasPendingMutation = false
        if table == "messages" {
            // Protect optimistic sends whose row is still pending in the
            // outbox (matched by client idempotency key).
            if let existing = try fetchMessage(id: rowId, in: context),
               pendingIdempotencyKeys.contains(existing.clientIdempotencyKey) {
                hasPendingMutation = true
            }
        }
        let decision = ConflictResolver.resolveTombstone(hasPendingLocalMutation: hasPendingMutation)

        if case .deleteRow = decision {
            try deleteRow(table: table, rowId: rowId, in: context)
        }

        // Record the tombstone either way: it proves we observed the
        // server's deletion and prevents a stale upsert from resurrecting
        // the row on a later replayed envelope.
        let existingTomb = try context.fetch(
            FetchDescriptor<CachedTombstone>(predicate: #Predicate {
                $0.table == table && $0.rowId == rowId
            })
        ).first
        if let existingTomb {
            existingTomb.deletedAt = deletedAt
        } else {
            context.insert(CachedTombstone(table: table, rowId: rowId, deletedAt: deletedAt))
        }
    }

    private static func deleteRow(table: String, rowId: String, in context: ModelContext) throws {
        switch table {
        case "actors":
            if let row = try fetchActor(id: rowId, in: context) { context.delete(row) }
        case "conversations":
            if let row = try fetchConversation(id: rowId, in: context) { context.delete(row) }
        case "conversation_members":
            // Members are keyed by (conversationId, actorId); the tombstone
            // id is the composite "conversationId|actorId".
            let parts = rowId.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2,
               let row = try fetchMember(conversationId: parts[0], actorId: parts[1], in: context) {
                context.delete(row)
            }
        case "messages":
            if let row = try fetchMessage(id: rowId, in: context) { context.delete(row) }
        case "message_bursts":
            if let row = try fetchMessageBurst(id: rowId, in: context) { context.delete(row) }
        case "moments":
            if let row = try fetchMoment(id: rowId, in: context) { context.delete(row) }
        case "moment_interactions":
            if let row = try fetchMomentInteraction(id: rowId, in: context) { context.delete(row) }
        case "friend_requests":
            if let row = try fetchFriendRequest(id: rowId, in: context) { context.delete(row) }
        case "relationships":
            if let row = try fetchRelationship(id: rowId, in: context) { context.delete(row) }
        case "group_invitations":
            if let row = try fetchGroupInvitation(id: rowId, in: context) { context.delete(row) }
        case "memory_items":
            if let row = try fetchMemoryItem(id: rowId, in: context) { context.delete(row) }
        case "world_events":
            if let row = try fetchWorldEvent(id: rowId, in: context) { context.delete(row) }
        default:
            break
        }
    }

    // MARK: - Upserts

    private static func upsertActor(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteActorDTO.self, upsert: upsert)
        if let existing = try fetchActor(id: upsert.id, in: context) {
            existing.socialGraphId = dto.socialGraphId
            existing.type = dto.type
            existing.publicName = dto.publicName
            existing.avatarAssetId = dto.avatarAssetId
            existing.templateId = dto.templateId
            existing.status = dto.status
            existing.updatedAt = Date()
        } else {
            context.insert(CachedActor(
                id: dto.id,
                socialGraphId: dto.socialGraphId,
                type: dto.type,
                publicName: dto.publicName,
                avatarAssetId: dto.avatarAssetId,
                templateId: dto.templateId,
                status: dto.status,
                updatedAt: Date(),
            ))
        }
    }

    private static func upsertConversation(_ upsert: SyncUpsert, in context: ModelContext) throws {
        try applyConversation(decode(RemoteConversationDTO.self, upsert: upsert), in: context)
    }

    private static func applyConversation(_ dto: RemoteConversationDTO, in context: ModelContext) throws {
        if let existing = try fetchConversation(id: dto.id, in: context) {
            existing.socialGraphId = dto.socialGraphId
            existing.type = dto.type
            existing.publicName = dto.publicName
            existing.createdByActorId = dto.createdByActorId
            existing.status = dto.status
        } else {
            context.insert(CachedConversation(
                id: dto.id,
                socialGraphId: dto.socialGraphId,
                type: dto.type,
                publicName: dto.publicName,
                createdByActorId: dto.createdByActorId,
                status: dto.status,
                createdAt: dto.createdAt,
            ))
        }
    }

    private static func upsertConversationMember(_ upsert: SyncUpsert, in context: ModelContext) throws {
        try applyConversationMember(decode(RemoteConversationMemberDTO.self, upsert: upsert), in: context)
    }

    private static func applyConversationMember(_ dto: RemoteConversationMemberDTO, in context: ModelContext) throws {
        if let existing = try fetchMember(conversationId: dto.conversationId, actorId: dto.actorId, in: context) {
            existing.status = dto.status
            existing.role = dto.role
            existing.invitedByActorId = dto.invitedByActorId
            existing.joinedAt = dto.joinedAt
            existing.leftAt = dto.leftAt
            existing.lastReadSequence = dto.lastReadSequence ?? existing.lastReadSequence
        } else {
            context.insert(CachedConversationMember(
                conversationId: dto.conversationId,
                actorId: dto.actorId,
                status: dto.status,
                role: dto.role,
                invitedByActorId: dto.invitedByActorId,
                joinedAt: dto.joinedAt,
                leftAt: dto.leftAt,
                lastReadSequence: dto.lastReadSequence ?? 0,
            ))
        }
    }

    private static func upsertMessage(_ dto: RemoteMessageDTO, id: String, in context: ModelContext) throws {
        if let existing = try fetchMessage(id: id, in: context) {
            existing.conversationId = dto.conversationId
            existing.senderActorId = dto.senderActorId
            existing.sequence = dto.sequence
            existing.kind = dto.kind
            existing.content = dto.content
            existing.structuredPayload = dto.structuredPayload
            existing.replyToMessageId = dto.replyToMessageId
            existing.burstId = dto.burstId
            existing.status = dto.status
            existing.editedAt = dto.editedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(CachedMessage(
                id: dto.id,
                conversationId: dto.conversationId,
                senderActorId: dto.senderActorId,
                sequence: dto.sequence,
                clientIdempotencyKey: dto.clientIdempotencyKey,
                kind: dto.kind,
                content: dto.content,
                structuredPayload: dto.structuredPayload,
                replyToMessageId: dto.replyToMessageId,
                burstId: dto.burstId,
                status: dto.status,
                createdAt: dto.createdAt,
                editedAt: dto.editedAt,
                deletedAt: dto.deletedAt,
            ))
        }
    }

    private static func upsertMessageBurst(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteMessageBurstDTO.self, upsert: upsert)
        if let existing = try fetchMessageBurst(id: upsert.id, in: context) {
            existing.lastMessageSequence = dto.lastMessageSequence
            existing.closedReason = dto.closedReason
            existing.closedAt = dto.closedAt
        } else {
            context.insert(CachedMessageBurst(
                id: dto.id,
                conversationId: dto.conversationId,
                senderActorId: dto.senderActorId,
                firstMessageSequence: dto.firstMessageSequence,
                lastMessageSequence: dto.lastMessageSequence,
                closedReason: dto.closedReason,
                openedAt: dto.openedAt,
                closedAt: dto.closedAt,
            ))
        }
    }

    private static func upsertMoment(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteMomentDTO.self, upsert: upsert)
        if let existing = try fetchMoment(id: upsert.id, in: context) {
            existing.actorId = dto.actorId
            existing.content = dto.content
            existing.audiencePolicy = dto.audiencePolicy
            existing.sourceEventId = dto.sourceEventId
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(CachedMoment(
                id: dto.id,
                actorId: dto.actorId,
                socialGraphId: dto.socialGraphId,
                content: dto.content,
                audiencePolicy: dto.audiencePolicy,
                sourceEventId: dto.sourceEventId,
                createdAt: dto.createdAt,
                deletedAt: dto.deletedAt,
            ))
        }
    }

    private static func upsertMomentInteraction(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteMomentInteractionDTO.self, upsert: upsert)
        if let existing = try fetchMomentInteraction(id: upsert.id, in: context) {
            existing.type = dto.type
            existing.content = dto.content
            existing.parentInteractionId = dto.parentInteractionId
        } else {
            context.insert(CachedMomentInteraction(
                id: dto.id,
                momentId: dto.momentId,
                actorId: dto.actorId,
                type: dto.type,
                content: dto.content,
                parentInteractionId: dto.parentInteractionId,
                createdAt: dto.createdAt,
            ))
        }
    }

    private static func upsertFriendRequest(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteFriendRequestDTO.self, upsert: upsert)
        if let existing = try fetchFriendRequest(id: upsert.id, in: context) {
            existing.status = dto.status
            existing.note = dto.note
        } else {
            context.insert(CachedFriendRequest(
                id: dto.id,
                senderActorId: dto.senderActorId,
                recipientActorId: dto.recipientActorId,
                status: dto.status,
                note: dto.note,
                createdAt: dto.createdAt,
            ))
        }
    }

    private static func upsertRelationship(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteRelationshipDTO.self, upsert: upsert)
        if let existing = try fetchRelationship(id: upsert.id, in: context) {
            existing.state = dto.state
            existing.updatedAt = dto.updatedAt
        } else {
            context.insert(CachedRelationship(
                id: dto.id,
                actorAId: dto.actorAId,
                actorBId: dto.actorBId,
                state: dto.state,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
            ))
        }
    }

    private static func upsertGroupInvitation(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteGroupInvitationDTO.self, upsert: upsert)
        if let existing = try fetchGroupInvitation(id: upsert.id, in: context) {
            existing.purpose = dto.purpose ?? ""
            existing.status = dto.status
            existing.decidedAt = dto.decidedAt
        } else {
            context.insert(CachedGroupInvitation(
                id: dto.id,
                conversationId: dto.conversationId,
                inviterActorId: dto.inviterActorId,
                inviteeActorId: dto.inviteeActorId,
                purpose: dto.purpose ?? "",
                status: dto.status,
                createdAt: dto.createdAt,
                decidedAt: dto.decidedAt,
            ))
        }
    }

    private static func upsertMemoryItem(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteMemoryItemDTO.self, upsert: upsert)
        if let existing = try fetchMemoryItem(id: upsert.id, in: context) {
            existing.objectiveFact = dto.objectiveFact
            existing.subjectiveInterpretation = dto.subjectiveInterpretation
            existing.confidence = dto.confidence
            existing.visibilityPolicy = dto.visibilityPolicy
            existing.sharePolicy = dto.sharePolicy
        } else {
            context.insert(CachedMemoryItem(
                id: dto.id,
                ownerActorId: dto.ownerActorId,
                relationshipId: dto.relationshipId,
                type: dto.type,
                objectiveFact: dto.objectiveFact,
                subjectiveInterpretation: dto.subjectiveInterpretation,
                confidence: dto.confidence,
                visibilityPolicy: dto.visibilityPolicy,
                sharePolicy: dto.sharePolicy,
                createdAt: dto.createdAt,
            ))
        }
    }

    private static func upsertWorldEvent(_ upsert: SyncUpsert, in context: ModelContext) throws {
        let dto = try decode(RemoteWorldEventDTO.self, upsert: upsert)
        if let existing = try fetchWorldEvent(id: upsert.id, in: context) {
            existing.type = dto.type
            existing.actorId = dto.actorId
            existing.occurredAt = dto.occurredAt
            existing.visibilityPolicy = dto.visibilityPolicy
        } else {
            context.insert(CachedWorldEvent(
                id: dto.id,
                socialGraphId: dto.socialGraphId,
                type: dto.type,
                actorId: dto.actorId,
                occurredAt: dto.occurredAt,
                visibilityPolicy: dto.visibilityPolicy,
                deletedAt: nil,
            ))
        }
    }

    // MARK: - Onboarding hydration (REST rows enter the sync flow)

    /// Apply REST-fetched onboarding rows through the same upsert path a
    /// `/v1/sync` envelope uses.
    ///
    /// The server creates the onboarding conversation without emitting
    /// `world_events` for it, so a fresh account's sync envelope is empty
    /// and the cache-first Chats list never sees the conversation.
    /// Hydration closes that gap client-side while keeping one cache
    /// identity per server row:
    ///   - idempotent by server id (a later authoritative replay is a
    ///     no-op, exactly like a repeated sync upsert)
    ///   - tombstoned rows are never resurrected
    ///   - a locally-advanced read cursor is never regressed
    ///   - pending outbox mutations are untouched (hydration only writes
    ///     server-identified rows)
    public static func hydrateOnboardingRows(
        conversation: RemoteConversationDTO?,
        messages: [RemoteMessageDTO],
        members: [RemoteConversationMemberDTO],
        in context: ModelContext,
    ) throws {
        if let conversation,
           try !hasTombstone(table: "conversations", rowId: conversation.id, in: context) {
            try applyConversation(conversation, in: context)
        }
        for dto in messages where dto.deletedAt == nil {
            if try hasTombstone(table: "messages", rowId: dto.id, in: context) { continue }
            try upsertMessage(dto, id: dto.id, in: context)
        }
        for dto in members {
            // Hydration only fills the read cursor in when absent or
            // behind: markReadLocally may have advanced it past the
            // server badge already.
            if let existing = try fetchMember(conversationId: dto.conversationId, actorId: dto.actorId, in: context) {
                if let readThrough = dto.lastReadSequence, readThrough > existing.lastReadSequence {
                    existing.lastReadSequence = readThrough
                }
                existing.status = dto.status
            } else {
                try applyConversationMember(dto, in: context)
            }
        }
        try context.save()
    }

    private static func hasTombstone(table: String, rowId: String, in context: ModelContext) throws -> Bool {
        let tombstones = try context.fetch(
            FetchDescriptor<CachedTombstone>(predicate: #Predicate {
                $0.table == table && $0.rowId == rowId
            }),
        )
        return !tombstones.isEmpty
    }

    // MARK: - Fetch helpers

    /// Per-type fetch helpers. SwiftData `#Predicate` key paths cannot be
    /// abstracted through a generic protocol without macro friction, so
    /// each id-keyed row gets a concrete lookup.

    private static func fetchActor(id: String, in context: ModelContext) throws -> CachedActor? {
        try context.fetch(FetchDescriptor<CachedActor>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchConversation(id: String, in context: ModelContext) throws -> CachedConversation? {
        try context.fetch(FetchDescriptor<CachedConversation>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchMessage(id: String, in context: ModelContext) throws -> CachedMessage? {
        try context.fetch(FetchDescriptor<CachedMessage>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchMessageBurst(id: String, in context: ModelContext) throws -> CachedMessageBurst? {
        try context.fetch(FetchDescriptor<CachedMessageBurst>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchMoment(id: String, in context: ModelContext) throws -> CachedMoment? {
        try context.fetch(FetchDescriptor<CachedMoment>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchMomentInteraction(id: String, in context: ModelContext) throws -> CachedMomentInteraction? {
        try context.fetch(FetchDescriptor<CachedMomentInteraction>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchFriendRequest(id: String, in context: ModelContext) throws -> CachedFriendRequest? {
        try context.fetch(FetchDescriptor<CachedFriendRequest>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchRelationship(id: String, in context: ModelContext) throws -> CachedRelationship? {
        try context.fetch(FetchDescriptor<CachedRelationship>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchGroupInvitation(id: String, in context: ModelContext) throws -> CachedGroupInvitation? {
        try context.fetch(FetchDescriptor<CachedGroupInvitation>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchMemoryItem(id: String, in context: ModelContext) throws -> CachedMemoryItem? {
        try context.fetch(FetchDescriptor<CachedMemoryItem>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchWorldEvent(id: String, in context: ModelContext) throws -> CachedWorldEvent? {
        try context.fetch(FetchDescriptor<CachedWorldEvent>(predicate: #Predicate { $0.id == id })).first
    }

    private static func fetchMember(conversationId: String, actorId: String, in context: ModelContext) throws -> CachedConversationMember? {
        try context.fetch(
            FetchDescriptor<CachedConversationMember>(predicate: #Predicate {
                $0.conversationId == conversationId && $0.actorId == actorId
            })
        ).first
    }

    /// Decode an upsert payload with the shared ISO-8601 (fractional
    /// seconds) strategy. A payload that fails to decode is logged and
    /// rethrown — SyncCoordinator records the failure without advancing
    /// the cursor past an unapplied change.
    private static func decode<T: Decodable>(_ type: T.Type, upsert: SyncUpsert) throws -> T {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601WithFractional
            return try decoder.decode(T.self, from: upsert.payload.data)
        } catch {
            logger.error(
                "sync payload decode failed for table \(upsert.table, privacy: .public): \(String(describing: error), privacy: .public)",
            )
            throw error
        }
    }
}
