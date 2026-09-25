import XCTest
@testable import Chat_Buddy_iOS

final class ConflictResolverTests: XCTestCase {
    func testUpsertWithoutPendingKeyAppliesServer() {
        let decision = ConflictResolver.resolveUpsert(
            messageClientIdempotencyKey: "k1",
            pendingIdempotencyKeys: [],
        )
        XCTAssertEqual(decision, .applyServer)
    }

    func testUpsertMatchingPendingKeyReconcilesOutbox() {
        let decision = ConflictResolver.resolveUpsert(
            messageClientIdempotencyKey: "k1",
            pendingIdempotencyKeys: ["k0", "k1"],
        )
        XCTAssertEqual(decision, .applyServerAndReconcileOutbox(idempotencyKey: "k1"))
    }

    func testUpsertWithoutClientKeyAppliesServer() {
        let decision = ConflictResolver.resolveUpsert(
            messageClientIdempotencyKey: nil,
            pendingIdempotencyKeys: ["k1"],
        )
        XCTAssertEqual(decision, .applyServer)
    }

    func testTombstoneDeletesWhenNoPendingWork() {
        XCTAssertEqual(
            ConflictResolver.resolveTombstone(hasPendingLocalMutation: false),
            .deleteRow,
        )
    }

    func testTombstoneKeepsLocalWhenMutationPending() {
        // Pending offline work must never be clobbered by a sync snapshot;
        // the server reconciles by idempotency key at flush time (§10).
        XCTAssertEqual(
            ConflictResolver.resolveTombstone(hasPendingLocalMutation: true),
            .keepLocal,
        )
    }
}
