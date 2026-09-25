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
///
/// Row application lives in `EventApplier` (§10) with the policy in
/// `ConflictResolver`; this actor owns transport, cursor movement, and
/// outbox reconciliation.
public actor SyncCoordinator {

    public struct ServerEnvelope: Sendable, Codable {
        public let cursor: String
        public let upserts: [SyncUpsert]
        public let tombstones: [SyncTombstone]
        public let serverTime: Date
        public let hasMore: Bool

        public init(
            cursor: String,
            upserts: [SyncUpsert],
            tombstones: [SyncTombstone],
            serverTime: Date,
            hasMore: Bool,
        ) {
            self.cursor = cursor
            self.upserts = upserts
            self.tombstones = tombstones
            self.serverTime = serverTime
            self.hasMore = hasMore
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
        // Snapshot the pending idempotency keys BEFORE applying so
        // ConflictResolver can protect optimistic work and reconcile
        // rows the server already accepted (§10).
        let pendingKeys = await MainActor.run { () -> Set<String> in
            Set(outbox.loadUnsettled(accountId: accountId).map(\.idempotencyKey))
        }
        let result = try await MainActor.run {
            try EventApplier.apply(
                envelope: envelope,
                in: context,
                pendingIdempotencyKeys: pendingKeys,
            )
        }
        await reconcileOutbox(result.reconciledIdempotencyKeys, accountId: accountId)
        await writeCursor(accountId: accountId, cursor: envelope.cursor)
        if envelope.hasMore {
            try await runSync(accountId: accountId)
        }
    }

    /// Idempotency-key reconciliation: the server accepted an optimistic
    /// mutation (its upsert carries our client idempotency key), so the
    /// outbox row can move to `accepted` instead of waiting for a flush.
    private func reconcileOutbox(_ keys: Set<String>, accountId: String) async {
        guard !keys.isEmpty else { return }
        await MainActor.run {
            let pending = outbox.loadUnsettled(accountId: accountId)
            for entry in pending where keys.contains(entry.idempotencyKey) {
                outbox.markAccepted(id: entry.id)
            }
        }
    }
}

// MARK: - Envelope row types

/// One ordered upsert: `table` names the row family, `id` the server row
/// identity, `payload` the raw JSON row (contract `sync.ts`).
public struct SyncUpsert: Sendable, Codable, Equatable {
    public let table: String
    public let id: String
    public let payload: ServerPayload

    public init(table: String, id: String, payload: ServerPayload) {
        self.table = table
        self.id = id
        self.payload = payload
    }
}

public struct SyncTombstone: Sendable, Codable, Equatable {
    public let table: String
    public let id: String
    public let deletedAt: Date

    public init(table: String, id: String, deletedAt: Date) {
        self.table = table
        self.id = id
        self.deletedAt = deletedAt
    }
}

/// Wrapper around the server-side JSON payload for a sync upsert.
public struct ServerPayload: Codable, Sendable, Equatable {
    public let data: Data

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.data = try encoder.encode(raw)
    }

    public init(data: Data) {
        self.data = data
    }

    public func encode(to encoder: Encoder) throws {
        try JSONDecoder().decode(JSONValue.self, from: data)
            .encode(to: encoder)
    }
}

enum JSONValue: Codable {
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
