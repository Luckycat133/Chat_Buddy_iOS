import Foundation
import SwiftData

/// Offline outbox per skill §"Make offline behavior explicit":
///   - client idempotency key
///   - queued / sending / accepted / failed / conflict state
///   - restart preserves outbox
///   - server reconciliation via APIError.isConflict
///   - never drop a mutation without an authoritative result
@MainActor
public final class OutboxStore {
    public enum State: String, Sendable, Codable {
        case queued
        case sending
        case accepted
        case failed
        case conflict
    }

    public struct Mutation: Sendable, Equatable {
        public let id: String
        public let accountId: String
        public let idempotencyKey: String
        public let method: String
        public let path: String
        public let bodyData: Data
        public let state: State
        public let attempts: Int
        public let lastError: String?
        public let createdAt: Date
        public let updatedAt: Date
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func enqueue(
        accountId: String,
        method: String,
        path: String,
        idempotencyKey: String,
        body: Data,
    ) throws -> Mutation {
        let id = UUID().uuidString
        let now = Date()
        let row = OutboxMutation(
            id: id,
            accountId: accountId,
            idempotencyKey: idempotencyKey,
            method: method,
            path: path,
            bodyData: body,
            state: State.queued.rawValue,
            attempts: 0,
            lastError: nil,
            createdAt: now,
            updatedAt: now,
        )
        context.insert(row)
        try context.save()
        return snapshot(row)
    }

    /// Replayable mutations. A `sending` row remains pending across a
    /// process interruption and must be recovered on the next launch.
    public func loadPending(accountId: String) -> [Mutation] {
        // SwiftData #Predicate key paths cannot reference enum cases —
        // capture the raw values as local constants instead.
        let queuedState = State.queued.rawValue
        let sendingState = State.sending.rawValue
        let failedState = State.failed.rawValue
        let descriptor = FetchDescriptor<OutboxMutation>(
            predicate: #Predicate { row in
                row.accountId == accountId
                    && (row.state == queuedState
                        || row.state == sendingState
                        || row.state == failedState)
            },
            sortBy: [SortDescriptor(\.createdAt)],
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map(snapshot)
    }

    /// Pending plus terminal conflicts for UI reconciliation. Conflict
    /// rows are intentionally not replayed automatically, but they must
    /// stay visible until a server read proves the message was accepted.
    public func loadUnsettled(accountId: String) -> [Mutation] {
        let conflictState = State.conflict.rawValue
        let descriptor = FetchDescriptor<OutboxMutation>(
            predicate: #Predicate { row in
                row.accountId == accountId && row.state == conflictState
            },
            sortBy: [SortDescriptor(\.createdAt)],
        )
        let conflicts = (try? context.fetch(descriptor)) ?? []
        return (loadPending(accountId: accountId) + conflicts.map(snapshot))
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func markSending(id: String) {
        if let row = fetch(id: id) {
            row.state = State.sending.rawValue
            row.attempts += 1
            row.updatedAt = Date()
            try? context.save()
        }
    }

    public func markAccepted(id: String) {
        if let row = fetch(id: id) {
            row.state = State.accepted.rawValue
            row.lastError = nil
            row.updatedAt = Date()
            try? context.save()
        }
    }

    public func markFailed(id: String, error: String) {
        if let row = fetch(id: id) {
            row.state = State.failed.rawValue
            row.lastError = error
            row.updatedAt = Date()
            try? context.save()
        }
    }

    public func markConflict(id: String) {
        if let row = fetch(id: id) {
            row.state = State.conflict.rawValue
            row.updatedAt = Date()
            try? context.save()
        }
    }

    /// Snapshot pending (queued/failed) mutations as pure values for the
    /// optimistic-row reducer. `content` is parsed from the stored body;
    /// the conversation id is parsed from the stored path
    /// (`/v1/conversations/{id}/messages`).
    public func pendingSnapshots(accountId: String) -> [OutboxMutationSnapshot] {
        loadUnsettled(accountId: accountId).map { entry in
            let body = (try? JSONDecoder().decode(SendMessageBodyShape.self, from: entry.bodyData))
            return OutboxMutationSnapshot(
                idempotencyKey: entry.idempotencyKey,
                conversationId: Self.conversationId(fromPath: entry.path),
                content: body?.content ?? "",
                senderActorId: nil,
                state: OutboxState(rawValue: entry.state.rawValue) ?? .queued,
                createdAt: entry.createdAt,
            )
        }
    }

    private struct SendMessageBodyShape: Decodable {
        let clientIdempotencyKey: String
        let content: String
    }

    static func conversationId(fromPath path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let idx = parts.firstIndex(of: "conversations"),
              idx + 1 < parts.count else { return "" }
        return parts[idx + 1]
    }

    public func delete(id: String) {
        if let row = fetch(id: id) {
            context.delete(row)
            try? context.save()
        }
    }

    public func clearAll(accountId: String) {
        let descriptor = FetchDescriptor<OutboxMutation>(
            predicate: #Predicate { $0.accountId == accountId },
        )
        if let rows = try? context.fetch(descriptor) {
            for row in rows { context.delete(row) }
            try? context.save()
        }
    }

    private func fetch(id: String) -> OutboxMutation? {
        let descriptor = FetchDescriptor<OutboxMutation>(
            predicate: #Predicate { $0.id == id },
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func snapshot(_ row: OutboxMutation) -> Mutation {
        Mutation(
            id: row.id,
            accountId: row.accountId,
            idempotencyKey: row.idempotencyKey,
            method: row.method,
            path: row.path,
            bodyData: row.bodyData,
            state: State(rawValue: row.state) ?? .queued,
            attempts: row.attempts,
            lastError: row.lastError,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
        )
    }
}