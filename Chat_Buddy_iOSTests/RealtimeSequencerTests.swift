import XCTest
@testable import Chat_Buddy_iOS

/// RealtimeSequencer: no event may be applied twice (IOS_IMPLEMENTATION §9).
final class RealtimeSequencerTests: XCTestCase {
    func testNewEventsAreDelivered() {
        var seq = RealtimeSequencer()
        XCTAssertEqual(seq.admit("evt-2"), .deliver)
        XCTAssertEqual(seq.admit("evt-3"), .deliver)
        XCTAssertEqual(seq.lastEventId, "evt-3")
    }

    func testDuplicateEventIsDropped() {
        var seq = RealtimeSequencer()
        XCTAssertEqual(seq.admit("evt-1"), .deliver)
        XCTAssertEqual(seq.admit("evt-1"), .duplicate)
    }

    func testStaleReplayIsDropped() {
        var seq = RealtimeSequencer()
        XCTAssertEqual(seq.admit("evt-5"), .deliver)
        // Server replays an older event after resume — must not re-apply.
        XCTAssertEqual(seq.admit("evt-4"), .stale)
        XCTAssertEqual(seq.lastEventId, "evt-5")
    }

    func testBoundedSeenSetEvictsOldest() {
        var seq = RealtimeSequencer(capacity: 2)
        XCTAssertEqual(seq.admit("a"), .deliver)
        XCTAssertEqual(seq.admit("b"), .deliver)
        XCTAssertEqual(seq.admit("c"), .deliver)
        // "a" was evicted from the seen set; re-delivery is allowed again
        // only because it is also stale-relative to "c" (UUIDv7 ordering).
        XCTAssertEqual(seq.admit("a"), .stale)
        XCTAssertEqual(seq.lastEventId, "c")
    }

    func testSeedSetsResumeBaseline() {
        var seq = RealtimeSequencer()
        seq.seed(lastEventId: "evt-42")
        XCTAssertEqual(seq.admit("evt-41"), .stale)
        XCTAssertEqual(seq.admit("evt-43"), .deliver)
    }

    func testSeedKeepsNewerExistingBaseline() {
        var seq = RealtimeSequencer()
        XCTAssertEqual(seq.admit("evt-99"), .deliver)
        seq.seed(lastEventId: "evt-10")
        XCTAssertEqual(seq.lastEventId, "evt-99")
    }
}
