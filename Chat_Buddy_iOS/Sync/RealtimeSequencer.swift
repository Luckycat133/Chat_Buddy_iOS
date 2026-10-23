import Foundation

/// Ordered-event admission control for the realtime channel per skill
/// §"Realtime client" + IOS_IMPLEMENTATION §9:
///   - No event may be applied twice (bounded seen-set dedup).
///   - Events are ordered; a replayed/stale event id is dropped instead of
///     being re-applied (server ids are UUIDv7, lexicographically sortable).
///   - The latest delivered id seeds the reconnect `last-event-id` header.
///
/// Extracted as a plain type so the dedup/ordering policy is unit-testable
/// without opening a socket. A final class (rather than a struct) lets the
/// actor-isolated `RealtimeClient` call `admit`/`seed` without passing
/// `inout` across the isolation boundary; all mutable state is guarded by
/// `lock`, so the type is safely `@unchecked Sendable`.
public final class RealtimeSequencer: @unchecked Sendable {
    public enum Verdict: Sendable, Equatable {
        /// New event — deliver to the applier exactly once.
        case deliver
        /// Already seen in this session — drop.
        case duplicate
        /// Older than the newest applied event (server replay after
        /// resume) — drop; delta sync covers anything actually missed.
        case stale
    }

    private let lock = NSLock()
    private var seen: Set<String> = []
    private var ring: [String] = []
    private let capacity: Int
    public private(set) var lastEventId: String?

    public init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    public func admit(_ eventId: String) -> Verdict {
        lock.lock()
        defer { lock.unlock() }
        if seen.contains(eventId) {
            return .duplicate
        }
        if let last = lastEventId, eventId < last {
            // Strictly older than the newest applied event. Equal ids are
            // caught by the seen-set above.
            return .stale
        }
        seen.insert(eventId)
        ring.append(eventId)
        if ring.count > capacity, let evicted = ring.first {
            ring.removeFirst()
            seen.remove(evicted)
        }
        lastEventId = eventId
        return .deliver
    }

    /// Explicitly seed the newest known id (e.g. restored cursor at boot)
    /// so pre-cursor replays are dropped after a reconnect.
    public func seed(lastEventId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard self.lastEventId == nil || lastEventId > self.lastEventId! else { return }
        self.lastEventId = lastEventId
    }
}
