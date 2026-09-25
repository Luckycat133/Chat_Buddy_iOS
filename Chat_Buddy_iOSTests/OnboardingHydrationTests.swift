import XCTest
import SwiftData
@testable import Chat_Buddy_iOS

/// Onboarding cache hydration tests: REST-fetched onboarding rows must
/// land in the same cache tables a `/v1/sync` envelope feeds, with the
/// same identity and idempotency guarantees (IOS_IMPLEMENTATION §10).
/// Covers the fresh-account gap where the server emits no `world_events`
/// for the onboarding conversation, leaving `/v1/sync` empty and the
/// cache-first Chats list blind to the session.
@MainActor
final class OnboardingHydrationTests: XCTestCase {
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

    // MARK: Fixtures (server-shaped rows)

    private func conversation(id: String = "conv-mira") -> RemoteConversationDTO {
        RemoteConversationDTO(
            id: id,
            socialGraphId: "graph-1",
            type: "direct",
            publicName: nil,
            createdByActorId: "actor-mira",
            status: "active",
            createdAt: Date(timeIntervalSince1970: 100),
        )
    }

    private func message(
        id: String,
        sequence: Int,
        sender: String = "actor-mira",
        deleted: Bool = false,
    ) -> RemoteMessageDTO {
        RemoteMessageDTO(
            id: id,
            conversationId: "conv-mira",
            senderActorId: sender,
            sequence: sequence,
            clientIdempotencyKey: "key-\(id)",
            kind: "text",
            content: "hello \(id)",
            structuredPayload: nil,
            replyToMessageId: nil,
            burstId: nil,
            status: "accepted",
            createdAt: Date(timeIntervalSince1970: Double(100 + sequence)),
            editedAt: nil,
            deletedAt: deleted ? Date(timeIntervalSince1970: 500) : nil,
        )
    }

    private func member(lastReadSequence: Int) -> RemoteConversationMemberDTO {
        RemoteConversationMemberDTO(
            id: nil,
            conversationId: "conv-mira",
            actorId: "me",
            status: "active",
            role: "member",
            invitedByActorId: nil,
            joinedAt: nil,
            leftAt: nil,
            lastReadSequence: lastReadSequence,
        )
    }

    // MARK: Rows land in the sync-backed tables

    func testHydrationPersistsConversationMessagesAndMember() throws {
        try EventApplier.hydrateOnboardingRows(
            conversation: conversation(),
            messages: [message(id: "m1", sequence: 1), message(id: "m2", sequence: 2)],
            members: [member(lastReadSequence: 1)],
            in: context,
        )

        let conversations = try context.fetch(FetchDescriptor<CachedConversation>())
        let messages = try context.fetch(FetchDescriptor<CachedMessage>()).sorted { $0.id < $1.id }
        let members = try context.fetch(FetchDescriptor<CachedConversationMember>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.id, "conv-mira")
        XCTAssertEqual(conversations.first?.type, "direct")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.map(\.sequence), [1, 2])
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.actorId, "me")
        XCTAssertEqual(members.first?.lastReadSequence, 1)
    }

    func testHydrationSkipsDeletedMessages() throws {
        try EventApplier.hydrateOnboardingRows(
            conversation: conversation(),
            messages: [
                message(id: "m1", sequence: 1),
                message(id: "m2", sequence: 2, deleted: true),
            ],
            members: [],
            in: context,
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).map(\.id), ["m1"])
    }

    // MARK: Identity + idempotency (same guarantees as a sync upsert)

    func testHydrationIsIdempotentAndPreservesOriginalTimestamp() throws {
        try EventApplier.hydrateOnboardingRows(
            conversation: conversation(),
            messages: [message(id: "m1", sequence: 1)],
            members: [],
            in: context,
        )
        let firstCreatedAt = try context.fetch(FetchDescriptor<CachedConversation>()).first?.createdAt

        // Second pass synthesizes a different placeholder timestamp (as
        // the repository would on a later onboarding resume) — server-id
        // identity still wins, no duplicate rows, timestamp preserved.
        try EventApplier.hydrateOnboardingRows(
            conversation: RemoteConversationDTO(
                id: "conv-mira",
                socialGraphId: "",
                type: "direct",
                publicName: nil,
                createdByActorId: "",
                status: "active",
                createdAt: Date(timeIntervalSince1970: 9_999),
            ),
            messages: [message(id: "m1", sequence: 1)],
            members: [],
            in: context,
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedConversation>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedConversation>()).first?.createdAt, firstCreatedAt)
    }

    // MARK: Tombstones are never resurrected by a REST replay

    func testHydrationSkipsTombstonedConversationAndMessages() throws {
        context.insert(CachedTombstone(
            table: "messages",
            rowId: "m1",
            deletedAt: Date(timeIntervalSince1970: 500),
        ))
        context.insert(CachedTombstone(
            table: "conversations",
            rowId: "conv-mira",
            deletedAt: Date(timeIntervalSince1970: 500),
        ))
        try context.save()

        try EventApplier.hydrateOnboardingRows(
            conversation: conversation(),
            messages: [message(id: "m1", sequence: 1), message(id: "m2", sequence: 2)],
            members: [],
            in: context,
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedConversation>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).map(\.id), ["m2"])
    }

    // MARK: Read cursor only moves forward

    func testHydrationDoesNotRegressLocallyAdvancedReadCursor() throws {
        context.insert(CachedConversationMember(
            conversationId: "conv-mira",
            actorId: "me",
            status: "active",
            role: "member",
            invitedByActorId: nil,
            joinedAt: nil,
            leftAt: nil,
            lastReadSequence: 9,
        ))
        try context.save()

        // Server badge is behind the local cursor: keep 9.
        try EventApplier.hydrateOnboardingRows(
            conversation: nil,
            messages: [],
            members: [member(lastReadSequence: 3)],
            in: context,
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CachedConversationMember>()).first?.lastReadSequence,
            9,
        )

        // Server badge is ahead: advance to 12.
        try EventApplier.hydrateOnboardingRows(
            conversation: nil,
            messages: [],
            members: [member(lastReadSequence: 12)],
            in: context,
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CachedConversationMember>()).first?.lastReadSequence,
            12,
        )
    }

    // MARK: Read-through synthesis from the server unread badge

    func testReadThroughSequenceMath() {
        // All read: cursor sits on the newest message.
        XCTAssertEqual(
            ConversationRepository.readThroughSequence(maxMessageSequence: 10, serverUnreadCount: 0),
            10,
        )
        // Three unread: cursor trails the newest by three.
        XCTAssertEqual(
            ConversationRepository.readThroughSequence(maxMessageSequence: 10, serverUnreadCount: 3),
            7,
        )
        // Degenerate badge (larger than history): clamp at zero.
        XCTAssertEqual(
            ConversationRepository.readThroughSequence(maxMessageSequence: 5, serverUnreadCount: 9),
            0,
        )
        XCTAssertEqual(
            ConversationRepository.readThroughSequence(maxMessageSequence: 5, serverUnreadCount: -1),
            5,
        )
    }
}
