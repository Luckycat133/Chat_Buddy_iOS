import XCTest
import SwiftData
@testable import Chat_Buddy_iOS

/// EventApplier tests per skill §"Sync coordinator": upsert idempotency,
/// tombstone application, unknown-table tolerance, outbox reconciliation.
/// Uses the in-memory container from `ModelContainerFactory`.
@MainActor
final class EventApplierTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try super.setUp()
        container = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Envelope builders (server-shaped JSON, contract sync.ts)

    private func envelope(
        upserts: [(table: String, id: String, payload: String)],
        tombstones: [(table: String, id: String)] = [],
    ) throws -> SyncCoordinator.ServerEnvelope {
        func payload(_ json: String) throws -> ServerPayload {
            guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
                throw NSError(domain: "test", code: 1)
            }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return ServerPayload(data: data)
        }
        return SyncCoordinator.ServerEnvelope(
            cursor: "cursor-1",
            upserts: try upserts.map { try SyncUpsert(table: $0.table, id: $0.id, payload: payload($0.payload)) },
            tombstones: tombstones.map {
                SyncTombstone(table: $0.table, id: $0.id, deletedAt: Date(timeIntervalSince1970: 100))
            },
            serverTime: Date(timeIntervalSince1970: 200),
            hasMore: false,
        )
    }

    private let actorJSON = """
    {"id":"actor-mira","socialGraphId":"graph-1","type":"character","publicName":"Mira","avatarAssetId":null,"templateId":"tpl-mira","status":"active"}
    """

    private let messageJSON = """
    {"id":"msg-1","conversationId":"conv-1","senderActorId":"00000000-0000-0000-0000-000000000001","sequence":3,"clientIdempotencyKey":"key-1","kind":"text","content":"hello","structuredPayload":null,"replyToMessageId":null,"burstId":"burst-1","status":"accepted","createdAt":"2026-09-24T10:00:00.000Z","editedAt":null,"deletedAt":null}
    """

    // MARK: - Upserts

    func testUpsertCreatesRowsForAllMappedTables() throws {
        let env = try envelope(upserts: [
            ("actors", "actor-mira", actorJSON),
            ("messages", "msg-1", messageJSON),
            ("conversations", "conv-1", """
            {"id":"conv-1","socialGraphId":"graph-1","type":"direct","publicName":null,"createdByActorId":"actor-mira","status":"active","createdAt":"2026-09-24T09:00:00.000Z"}
            """),
            ("conversation_members", "member-1", """
            {"id":"member-1","conversationId":"conv-1","actorId":"actor-mira","status":"active","role":"member","invitedByActorId":null,"joinedAt":"2026-09-24T09:01:00.000Z","leftAt":null,"lastReadSequence":2}
            """),
            ("message_bursts", "burst-1", """
            {"id":"burst-1","conversationId":"conv-1","senderActorId":"00000000-0000-0000-0000-000000000001","firstMessageSequence":3,"lastMessageSequence":3,"closedReason":null,"openedAt":"2026-09-24T10:00:00.000Z","closedAt":null}
            """),
            ("group_invitations", "inv-1", """
            {"id":"inv-1","conversationId":"conv-1","inviterActorId":"actor-mira","inviteeActorId":"actor-max","purpose":"hello","status":"pending","createdAt":"2026-09-24T09:00:00.000Z","decidedAt":null}
            """),
            ("world_events", "evt-1", """
            {"id":"evt-1","socialGraphId":"graph-1","type":"message_sent","actorId":"actor-mira","subjectActorIds":[],"conversationId":"conv-1","momentId":null,"payload":{},"occurredAt":"2026-09-24T10:00:00.000Z","causedByEventId":null,"idempotencyKey":"message_sent:m-1","visibilityPolicy":{"conversation":["conv-1"]}}
            """),
        ])
        let result = try EventApplier.apply(envelope: env, in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedActor>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedConversation>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedConversationMember>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessageBurst>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedGroupInvitation>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedWorldEvent>()).count, 1)
        XCTAssertTrue(result.skippedTables.isEmpty)
        // Cursor is NOT advanced by the applier — the coordinator owns it.
    }

    func testReapplyingSameEnvelopeDoesNotDuplicateRows() throws {
        let env = try envelope(upserts: [
            ("actors", "actor-mira", actorJSON),
            ("messages", "msg-1", messageJSON),
        ])
        _ = try EventApplier.apply(envelope: env, in: context)
        _ = try EventApplier.apply(envelope: env, in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedActor>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).count, 1)
    }

    func testMessageUpsertUpdatesAllFields() throws {
        _ = try EventApplier.apply(envelope: envelope(upserts: [
            ("messages", "msg-1", messageJSON),
        ]), in: context)
        let editedJSON = messageJSON
            .replacingOccurrences(of: "\"content\":\"hello\"", with: "\"content\":\"hello edited\"")
            .replacingOccurrences(of: "\"sequence\":3", with: "\"sequence\":4")
            .replacingOccurrences(of: "\"editedAt\":null", with: "\"editedAt\":\"2026-09-24T11:00:00.000Z\"")
        _ = try EventApplier.apply(envelope: envelope(upserts: [
            ("messages", "msg-1", editedJSON),
        ]), in: context)

        let row = try context.fetch(FetchDescriptor<CachedMessage>()).first
        XCTAssertEqual(row?.content, "hello edited")
        XCTAssertEqual(row?.sequence, 4)
        XCTAssertNotNil(row?.editedAt)
    }

    func testUnknownTableIsSkippedAndReported() throws {
        let env = try envelope(upserts: [
            ("brand_new_server_table", "row-1", "{}"),
            ("actors", "actor-mira", actorJSON),
        ])
        let result = try EventApplier.apply(envelope: env, in: context)
        XCTAssertEqual(result.skippedTables, ["brand_new_server_table"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedActor>()).count, 1)
    }

    // MARK: - Tombstones

    func testTombstoneDeletesRowAndRecordsTombstone() throws {
        _ = try EventApplier.apply(envelope: envelope(upserts: [
            ("messages", "msg-1", messageJSON),
        ]), in: context)

        let result = try EventApplier.apply(envelope: envelope(
            upserts: [],
            tombstones: [("messages", "msg-1")],
        ), in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).count, 0)
        let tomb = try context.fetch(FetchDescriptor<CachedTombstone>()).first
        XCTAssertEqual(tomb?.table, "messages")
        XCTAssertEqual(tomb?.rowId, "msg-1")
        XCTAssertTrue(result.reconciledIdempotencyKeys.isEmpty)
    }

    func testTombstonePreservesRowWithPendingOutboxMutation() throws {
        _ = try EventApplier.apply(envelope: envelope(upserts: [
            ("messages", "msg-1", messageJSON),
        ]), in: context)

        // The row's client idempotency key is still queued in the outbox.
        _ = try EventApplier.apply(
            envelope: envelope(upserts: [], tombstones: [("messages", "msg-1")]),
            in: context,
            pendingIdempotencyKeys: ["key-1"],
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedTombstone>()).count, 1)
    }

    // MARK: - Idempotency reconciliation

    func testUpsertMatchingPendingKeyReportsReconciliation() throws {
        let result = try EventApplier.apply(envelope: envelope(upserts: [
            ("messages", "msg-1", messageJSON),
        ]), in: context, pendingIdempotencyKeys: ["key-1"])

        XCTAssertEqual(result.reconciledIdempotencyKeys, ["key-1"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).count, 1)
    }

    // MARK: - Member composite tombstone

    func testMemberTombstoneUsesCompositeId() throws {
        _ = try EventApplier.apply(envelope: envelope(upserts: [
            ("conversation_members", "member-1", """
            {"id":"member-1","conversationId":"conv-1","actorId":"actor-mira","status":"active","role":"member","invitedByActorId":null,"joinedAt":null,"leftAt":null,"lastReadSequence":0}
            """),
        ]), in: context)
        _ = try EventApplier.apply(envelope: envelope(
            upserts: [],
            tombstones: [("conversation_members", "conv-1|actor-mira")],
        ), in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedConversationMember>()).count, 0)
    }
}
