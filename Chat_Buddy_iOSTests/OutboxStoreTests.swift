import XCTest
import SwiftData
@testable import Chat_Buddy_iOS

@MainActor
final class OutboxStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var outbox: OutboxStore!

    override func setUp() async throws {
        try super.setUp()
        container = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        outbox = OutboxStore(context: ModelContext(container))
    }

    override func tearDown() async throws {
        container = nil
        outbox = nil
        try await super.tearDown()
    }

    func testEnqueuePersistsWithQueuedState() throws {
        let body = Data("{\"hello\":1}".utf8)
        let mutation = try outbox.enqueue(
            accountId: "user-1",
            method: "POST",
            path: "/v1/conversations/x/messages",
            idempotencyKey: "abc",
            body: body,
        )
        XCTAssertEqual(mutation.state, .queued)
        XCTAssertEqual(outbox.loadPending(accountId: "user-1").count, 1)
    }

    func testStateTransitionsAreRecorded() throws {
        let mutation = try outbox.enqueue(
            accountId: "user-1",
            method: "POST",
            path: "/v1/x",
            idempotencyKey: "k1",
            body: Data(),
        )
        outbox.markSending(id: mutation.id)
        XCTAssertEqual(outbox.loadPending(accountId: "user-1").count, 1)
        outbox.markAccepted(id: mutation.id)
        XCTAssertEqual(outbox.loadPending(accountId: "user-1").count, 0)
        outbox.delete(id: mutation.id)
    }

    func testFailureKeepsMutationPendingForRetry() throws {
        let mutation = try outbox.enqueue(
            accountId: "user-1",
            method: "POST",
            path: "/v1/x",
            idempotencyKey: "k2",
            body: Data(),
        )
        outbox.markSending(id: mutation.id)
        outbox.markFailed(id: mutation.id, error: "boom")
        XCTAssertEqual(outbox.loadPending(accountId: "user-1").count, 1)
        outbox.markConflict(id: mutation.id)
        XCTAssertEqual(outbox.loadPending(accountId: "user-1").count, 0)
    }

    func testClearAllRemovesEveryMutationForAccount() throws {
        _ = try outbox.enqueue(
            accountId: "user-1",
            method: "POST",
            path: "/v1/x",
            idempotencyKey: "k3",
            body: Data(),
        )
        _ = try outbox.enqueue(
            accountId: "user-2",
            method: "POST",
            path: "/v1/x",
            idempotencyKey: "k4",
            body: Data(),
        )
        outbox.clearAll(accountId: "user-1")
        XCTAssertEqual(outbox.loadPending(accountId: "user-1").count, 0)
        XCTAssertEqual(outbox.loadPending(accountId: "user-2").count, 1)
    }
}