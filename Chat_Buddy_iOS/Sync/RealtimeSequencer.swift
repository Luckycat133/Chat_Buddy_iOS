import Foundation

/// Ordered-event admission control for the realtime channel per skill
/// §"Realtime client" + IOS_IMPLEMENTATION §9:
///   - No event may be applied twice (bounded seen-set dedup).
///   - Events are ordered; a replayed/stale event id is dropped instead of
///     being re-applied (server ids are UUIDv7, lexicographically sortable).
///   - The latest delivered id seeds the reconnect `last-event-id` header.
///
/// Extracted as a plain struct so the dedup/ordering policy is unit-testable
/// without opening a socket.
public struct RealtimeSequencer: Sendable {
    public enum Verdict: Sendable, Equatable {
        /// New event — deliver to the applier exactly once.
        case deliver
        /// Already seen in this session — drop.
        case duplicate
        /// Older than the newest applied event (server replay after
        /// resume) — drop; delta sync covers anything actually missed.
        case stale
    }

    private var seen: Set<String> = []
    private var ring: [String] = []
    private let capacity: Int
    public private(set) var lastEventId: String?

    public init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    public mutating func admit(_ eventId: String) -> Verdict {
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
    public mutating func seed(lastEventId: String) {
        guard self.lastEventId == nil || lastEventId > self.lastEventId! else { return }
        self.lastEventId = lastEventId
    }
}
