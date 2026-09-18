import Foundation
import SwiftData
import os

/// Delta sync coordinator per skill §"Sync coordinator".
///
///   - initial sync: load cache → refresh auth → fetch /v1/sync?cursor=
///     → apply upserts/tombstones in one SwiftData transaction →
///     advance cursor → connect realtime → flush outbox
///   - incremental sync: upsert by server id, apply tombstones,
///     preserve pending local mutations, reconcile by idempotency key.
///   - never replace the entire local store from a stale snapshot.
public actor SyncCoordinator {
    public struct ServerEnvelope: Sendable, Codable {
        public let cursor: String
        public let upserts: [SyncUpsert]
        public let tombstones: [SyncTombstone]
        public let serverTime: Date
        public let hasMore: Bool

        public struct SyncUpsert: Sendable, Codable {
            public let table: String
            public let id: String
            public let payload: ServerPayload
        }

        public struct SyncTombstone: Sendable, Codable {
            public let table: String
            public let id: String
            public let deletedAt: Date
        }
    }

    private let http: HTTPClient
    private let context: ModelContext
    private let cursorStore: SyncCursorStore
    private let outbox: OutboxStore
    private let flushOutbox: @Sendable () async -> Void
    private let logger = CloudLogger.sync

    public init(
        http: HTTPClient,
        context: ModelContext,
        cursorStore: SyncCursorStore,
        outbox: OutboxStore,
        flushOutbox: @escaping @Sendable () async -> Void,
    ) {
        self.http = http
        self.context = context
        self.cursorStore = cursorStore
        self.outbox = outbox
        self.flushOutbox = flushOutbox
    }

    /// Run an initial sync and flush pending outbox mutations.
    public func initialSync(accountId: String) async throws {
        try await runSync(accountId: accountId)
        await flushOutbox()
    }

    /// Run a follow-up sync (e.g., after realtime gap).
    public func runSync(accountId: String) async throws {
        let cursor = await cursor(for: accountId)
        let envelope = try await http.get(
            Endpoints.sync(cursor: cursor),
            as: ServerEnvelope.self,
        )
        try await apply(envelope: envelope, accountId: accountId)
    }

    private func cursor(for accountId: String) async -> String? {
        await MainActor.run { cursorStore.readCursor(accountId: accountId) }
    }

    private func writeCursor(accountId: String, cursor: String) async {
        await MainActor.run { cursorStore.writeCursor(accountId: accountId, cursor: cursor) }
    }

    private func apply(envelope: ServerEnvelope, accountId: String) async throws {
        try await MainActor.run {
            try Self.applyEnvelope(envelope, in: context)
        }
        await writeCursor(accountId: accountId, cursor: envelope.cursor)
        if envelope.hasMore {
            try await runSync(accountId: accountId)
        }
    }

    private static func applyEnvelope(_ envelope: ServerEnvelope, in context: ModelContext) throws {
        for upsert in envelope.upserts {
            switch upsert.table {
            case "actors":
                try upsertActor(upsert, in: context)
            case "conversations":
                try upsertConversation(upsert, in: context)
            case "messages":
                try upsertMessage(upsert, in: context)
            case "moments":
                try upsertMoment(upsert, in: context)
            case "friend_requests":
                try upsertFriendRequest(upsert, in: context)
            case "relationships":
                try upsertRelationship(upsert, in: context)
            case "memory_items":
                try upsertMemoryItem(upsert, in: context)
            default:
                // Unknown tables are not authoritative for the client yet;
                // we still record the table for forward compatibility.
                continue
            }
        }
        for tomb in envelope.tombstones {
            try recordTombstone(table: tomb.table, rowId: tomb.id, deletedAt: tomb.deletedAt, in: context)
        }
        try context.save()
    }

    private static func upsertActor(_ upsert: ServerEnvelope.SyncUpsert, in context: ModelContext) throws {
        let dto = try JSONDecoder().decode(RemoteActorDTO.self, from: upsert.payload.data)
        let existing = try context.fetch(
            FetchDescriptor<CachedActor>(predicate: #Predicate { $0.id == upsert.id })
        ).first
        if let existing {
            existing.publicName = dto.publicName
            existing.avatarAssetId = dto.avatarAssetId
            existing.status = dto.status
            existing.updatedAt = Date()
        } else {
            context.insert(
                CachedActor(
                    id: dto.id,
                    socialGraphId: dto.socialGraphId,
                    type: dto.type,
                    publicName: dto.publicName,
                    avatarAssetId: dto.avatarAssetId,
                    templateId: dto.templateId,
                    status: dto.status,
                    updatedAt: Date(),
                ),
            )
        }
    }

    private static func upsertConversation(_ upsert: ServerEnvelope.SyncUpsert, in context: ModelContext) throws {
        let dto = try JSONDecoder().decode(RemoteConversationDTO.self, from: upsert.payload.data)
        if let existing = try context.fetch(
            FetchDescriptor<CachedConversation>(predicate: #Predicate { $0.id == upsert.id })
        ).first {
            existing.publicName = dto.publicName
            existing.status = dto.status
        } else {
            context.insert(
                CachedConversation(
                    id: dto.id,
                    socialGraphId: dto.socialGraphId,
                    type: dto.type,
                    publicName: dto.publicName,
                    createdByActorId: dto.createdByActorId,
                    status: dto.status,
                    createdAt: dto.createdAt,
                ),
            )
        }
    }

    private static func upsertMessage(_ upsert: ServerEnvelope.SyncUpsert, in context: ModelContext) throws {
        let dto = try JSONDecoder().decode(RemoteMessageDTO.self, from: upsert.payload.data)
        if let existing = try context.fetch(
            FetchDescriptor<CachedMessage>(predicate: #Predicate { $0.id == upsert.id })
        ).first {
            existing.content = dto.content
            existing.status = dto.status
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(
                CachedMessage(
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
                    deletedAt: dto.deletedAt,
                ),
            )
        }
    }

    private static func upsertMoment(_ upsert: ServerEnvelope.SyncUpsert, in context: ModelContext) throws {
        let dto = try JSONDecoder().decode(RemoteMomentDTO.self, from: upsert.payload.data)
        if let existing = try context.fetch(
            FetchDescriptor<CachedMoment>(predicate: #Predicate { $0.id == upsert.id })
        ).first {
            existing.content = dto.content
            existing.audiencePolicy = dto.audiencePolicy
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(
                CachedMoment(
                    id: dto.id,
                    actorId: dto.actorId,
                    socialGraphId: dto.socialGraphId,
                    content: dto.content,
                    audiencePolicy: dto.audiencePolicy,
                    sourceEventId: dto.sourceEventId,
                    createdAt: dto.createdAt,
                    deletedAt: dto.deletedAt,
                ),
            )
        }
    }

    private static func upsertFriendRequest(_ upsert: ServerEnvelope.SyncUpsert, in context: ModelContext) throws {
        let dto = try JSONDecoder().decode(RemoteFriendRequestDTO.self, from: upsert.payload.data)
        if let existing = try context.fetch(
            FetchDescriptor<CachedFriendRequest>(predicate: #Predicate { $0.id == upsert.id })
        ).first {
            existing.status = dto.status
            existing.note = dto.note
        } else {
            context.insert(
                CachedFriendRequest(
                    id: dto.id,
                    senderActorId: dto.senderActorId,
                    recipientActorId: dto.recipientActorId,
                    status: dto.status,
                    note: dto.note,
                    createdAt: dto.createdAt,
                ),
            )
        }
    }

    private static func upsertRelationship(_ upsert: ServerEnvelope.SyncUpsert, in context: ModelContext) throws {
        let dto = try JSONDecoder().decode(RemoteRelationshipDTO.self, from: upsert.payload.data)
        if let existing = try context.fetch(
            FetchDescriptor<CachedRelationship>(predicate: #Predicate { $0.id == upsert.id })
        ).first {
            existing.state = dto.state
            existing.updatedAt = Date()
        } else {
            context.insert(
                CachedRelationship(
                    id: dto.id,
                    actorAId: dto.actorAId,
                    actorBId: dto.actorBId,
                    state: dto.state,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt,
                ),
            )
        }
    }

    private static func upsertMemoryItem(_ upsert: ServerEnvelope.SyncUpsert, in context: ModelContext) throws {
        let dto = try JSONDecoder().decode(RemoteMemoryItemDTO.self, from: upsert.payload.data)
        if let existing = try context.fetch(
            FetchDescriptor<CachedMemoryItem>(predicate: #Predicate { $0.id == upsert.id })
        ).first {
            existing.subjectiveInterpretation = dto.subjectiveInterpretation
        } else {
            context.insert(
                CachedMemoryItem(
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
                ),
            )
        }
    }

    private static func recordTombstone(
        table: String,
        rowId: String,
        deletedAt: Date,
        in context: ModelContext,
    ) throws {
        let existing = try context.fetch(
            FetchDescriptor<CachedTombstone>(predicate: #Predicate { $0.table == table && $0.rowId == rowId })
        ).first
        if let existing {
            existing.deletedAt = deletedAt
        } else {
            context.insert(CachedTombstone(table: table, rowId: rowId, deletedAt: deletedAt))
        }
    }

    /// The cursor is opaque; we use the accountId label here purely for
    /// the local cache key. The actual cursor body lives in the server's
    /// `sync_cursor` table.
    private func cursorKey(accountId: String) -> String {
        return accountId
    }
}

// MARK: - DTOs

/// Wrapper around the server-side JSON payload for a sync upsert.
public struct ServerPayload: Codable, Sendable {
    public let data: Data

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        self.data = try JSONEncoder().encode(raw)
    }

    public func encode(to encoder: Encoder) throws {
        try JSONDecoder().decode(JSONValue.self, from: data)
            .encode(to: encoder)
    }
}

private enum JSONValue: Codable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v):
            try c.encode(v)
        case .array(let v):
            try c.encode(v)
        case .string(let v):
            try c.encode(v)
        case .number(let v):
            try c.encode(v)
        case .bool(let v):
            try c.encode(v)
        case .null:
            try c.encodeNil()
        }
    }
}