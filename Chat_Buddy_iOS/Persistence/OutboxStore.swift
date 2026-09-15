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

    public func loadPending(accountId: String) -> [Mutation] {
        // SwiftData #Predicate key paths cannot reference enum cases —
        // capture the raw values as local constants instead.
        let queuedState = State.queued.rawValue
        let failedState = State.failed.rawValue
        let descriptor = FetchDescriptor<OutboxMutation>(
            predicate: #Predicate { row in
                row.accountId == accountId
                    && (row.state == queuedState
                        || row.state == failedState)
            },
            sortBy: [SortDescriptor(\.createdAt)],
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map(snapshot)
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