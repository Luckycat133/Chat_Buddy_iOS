import Foundation

/// Sync conflict policy per skill §"Make offline behavior explicit" +
/// DOMAIN_ARCHITECTURE §13:
///   - The server is authoritative for rows we are not mutating locally.
///   - Pending offline mutations (outbox `queued`/`sending`/`failed`) are
///     never clobbered by a sync snapshot; the server reconciles them by
///     client idempotency key when the outbox flushes.
///   - Tombstones delete rows, but not rows whose local mutation is still
///     pending — the flush/CONFLICT handshake resolves those.
///   - A stale snapshot can never wholesale replace the cache: upserts are
///     keyed by server id and tombstones are explicit.
public enum ConflictResolver {

    public enum Action: Sendable, Equatable {
        /// Apply the server row over the cached row.
        case applyServer
        /// Apply the server row AND reconcile the matching pending outbox
        /// mutation (the server accepted our idempotency key).
        case applyServerAndReconcileOutbox(idempotencyKey: String)
        /// Keep the local row untouched (pending local work wins).
        case keepLocal
        /// Delete the cached row (server tombstone).
        case deleteRow
    }

    /// A server upsert arrived. When the upserted message carries a client
    /// idempotency key that is still pending in the outbox, the server has
    /// accepted the optimistic mutation — apply and reconcile.
    public static func resolveUpsert(
        messageClientIdempotencyKey: String?,
        pendingIdempotencyKeys: Set<String>,
    ) -> Action {
        if let key = messageClientIdempotencyKey, pendingIdempotencyKeys.contains(key) {
            return .applyServerAndReconcileOutbox(idempotencyKey: key)
        }
        return .applyServer
    }

    /// A server tombstone arrived.
    ///
    /// `hasPendingLocalMutation` is true when the targeted row belongs to
    /// work still queued/sending in the outbox (matched by the row's client
    /// idempotency key for messages). Pending work is preserved; the next
    /// sync after the flush settles the state.
    public static func resolveTombstone(
        hasPendingLocalMutation: Bool,
    ) -> Action {
        hasPendingLocalMutation ? .keepLocal : .deleteRow
    }
}
