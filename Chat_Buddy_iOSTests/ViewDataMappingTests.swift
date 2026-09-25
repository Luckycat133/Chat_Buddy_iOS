import XCTest
@testable import Chat_Buddy_iOS

/// Remote → Cached → ViewData mapping tests per skill §"API models and
/// contract discipline" (DTOs must not become long-lived SwiftUI state).
@MainActor
final class ViewDataMappingTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
    }

    func testActorViewDataMapsCharacter() throws {
        let cached = CachedActor(
            id: "actor-1",
            socialGraphId: "g1",
            type: "character",
            publicName: "Mira",
            avatarAssetId: nil,
            templateId: "tpl-mira",
            status: "active",
            updatedAt: Date(),
        )
        let view = ActorViewData(cached: cached)
        XCTAssertEqual(view.id, "actor-1")
        XCTAssertEqual(view.displayName, "Mira")
        XCTAssertTrue(view.isCharacter)
        XCTAssertEqual(view.actorType, .character)
    }

    func testActorViewDataUnknownTypeIsNotCharacter() throws {
        let cached = CachedActor(
            id: "actor-2",
            socialGraphId: "g1",
            type: "synthetic_agent_v9",
            publicName: "Zeta",
            avatarAssetId: nil,
            templateId: nil,
            status: "active",
            updatedAt: Date(),
        )
        let view = ActorViewData(cached: cached)
        XCTAssertEqual(view.actorType, .unknown("synthetic_agent_v9"))
        XCTAssertFalse(view.isCharacter)
    }

    func testConversationViewDataFlagsGroupAndHidden() throws {
        let group = CachedConversation(
            id: "c1", socialGraphId: "g1", type: "group",
            publicName: "Trip crew", createdByActorId: "a1",
            status: "active", createdAt: Date(),
        )
        XCTAssertTrue(ConversationViewData(cached: group).isGroup)

        let hidden = CachedConversation(
            id: "c2", socialGraphId: "g1", type: "hidden_ai_direct",
            publicName: nil, createdByActorId: "a1",
            status: "active", createdAt: Date(),
        )
        let hiddenView = ConversationViewData(cached: hidden)
        XCTAssertTrue(hiddenView.isHiddenAiDirect)
        XCTAssertFalse(hiddenView.isGroup)
    }

    func testMessageViewDataHumanDetectionAndDeletedRedaction() throws {
        let human = CachedMessage(
            id: "m1", conversationId: "c1",
            senderActorId: "00000000-0000-0000-0000-000000000001",
            sequence: 1, clientIdempotencyKey: "k1", kind: "text",
            content: "hello", structuredPayload: nil,
            replyToMessageId: nil, burstId: nil, status: "accepted",
            createdAt: Date(), editedAt: nil, deletedAt: nil,
        )
        let humanView = MessageViewData(cached: human)
        XCTAssertTrue(humanView.isFromHuman)
        XCTAssertEqual(humanView.text, "hello")

        let character = CachedMessage(
            id: "m2", conversationId: "c1",
            senderActorId: "11111111-2222-3333-4444-555555555555",
            sequence: 2, clientIdempotencyKey: "k2", kind: "text",
            content: "hi there", structuredPayload: nil,
            replyToMessageId: nil, burstId: nil, status: "accepted",
            createdAt: Date(), editedAt: nil, deletedAt: nil,
        )
        XCTAssertFalse(MessageViewData(cached: character).isFromHuman)

        let deleted = CachedMessage(
            id: "m3", conversationId: "c1",
            senderActorId: "00000000-0000-0000-0000-000000000001",
            sequence: 3, clientIdempotencyKey: "k3", kind: "text",
            content: "typo", structuredPayload: nil,
            replyToMessageId: nil, burstId: nil, status: "accepted",
            createdAt: Date(), editedAt: nil,
            deletedAt: Date(),
        )
        let deletedView = MessageViewData(cached: deleted)
        XCTAssertTrue(deletedView.isDeleted)
        XCTAssertEqual(deletedView.text, "")
    }

    func testMomentViewDataDeletedRedaction() throws {
        let moment = CachedMoment(
            id: "mo1", actorId: "a1", socialGraphId: "g1",
            content: "sunset pic", audiencePolicy: "friends",
            sourceEventId: nil, createdAt: Date(), deletedAt: nil,
        )
        XCTAssertEqual(MomentViewData(cached: moment).text, "sunset pic")

        let removed = CachedMoment(
            id: "mo2", actorId: "a1", socialGraphId: "g1",
            content: "regret", audiencePolicy: "friends",
            sourceEventId: nil, createdAt: Date(), deletedAt: Date(),
        )
        let view = MomentViewData(cached: removed)
        XCTAssertTrue(view.isDeleted)
        XCTAssertEqual(view.text, "")
    }
}
