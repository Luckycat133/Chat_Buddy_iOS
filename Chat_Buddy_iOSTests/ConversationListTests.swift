import Foundation
import SwiftData
import Testing
@testable import Chat_Buddy_iOS

/// Exercise the actual SwiftData projection consumed by ChatsRootView,
/// including conversations that have never received a message.
@MainActor
struct ConversationListTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let repository: ConversationRepository

    init() throws {
        let container = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        let context = ModelContext(container)
        let environment = AppEnvironment.development
        self.container = container
        self.context = context
        self.repository = ConversationRepository(
            http: HTTPClient(
                environment: environment,
                session: AuthSession(environment: environment, service: "conversation-list-tests-\(UUID())"),
            ),
            context: context,
            outbox: OutboxStore(context: context),
            accountIdProvider: { "account-test" },
        )
    }

    @Test
    func emptyGroupRemainsVisibleWithCreationTimeAndNoUnreadMessages() async throws {
        insertConversation(id: "group-empty", createdAt: 100)
        try context.save()

        let items = await repository.cachedConversationList()
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.id == "group-empty")
        #expect(item.publicName == "Group group-empty")
        #expect(item.lastMessagePreview == nil)
        #expect(item.unreadCount == 0)
        #expect(item.lastActivityAt == Date(timeIntervalSince1970: 100))
    }

    @Test
    func emptyDirectConversationPreservesItsFallbackTitle() async throws {
        insertConversation(id: "direct-empty", type: "direct", name: "Mira", createdAt: 100)
        try context.save()

        let items = await repository.cachedConversationList()
        let item = try #require(items.first)
        #expect(item.publicName == "Mira")
        #expect(item.lastMessagePreview == nil)
    }

    @Test
    func deletingLastMessageDoesNotDeleteConversation() async throws {
        insertConversation(id: "group-deleted-message", createdAt: 100)
        insertMessage(id: "deleted", conversationId: "group-deleted-message", sequence: 1, createdAt: 200, deleted: true)
        try context.save()

        let items = await repository.cachedConversationList()
        let item = try #require(items.first)
        #expect(item.id == "group-deleted-message")
        #expect(item.lastMessagePreview == nil)
        #expect(item.unreadCount == 0)
        #expect(item.lastActivityAt == Date(timeIntervalSince1970: 100))
    }

    @Test
    func hiddenAndTombstonedConversationsStayExcludedWithOrWithoutMessages() async throws {
        insertConversation(id: "visible", createdAt: 100)
        for hasMessages in [false, true] {
            let hiddenId = "hidden-\(hasMessages)"
            let deletedId = "deleted-\(hasMessages)"
            insertConversation(id: hiddenId, type: "hidden_ai_direct", createdAt: 200)
            insertConversation(id: deletedId, createdAt: 300)
            context.insert(CachedTombstone(table: "conversations", rowId: deletedId, deletedAt: Date()))
            if hasMessages {
                insertMessage(id: "\(hiddenId)-message", conversationId: hiddenId, sequence: 1, createdAt: 400)
                insertMessage(id: "\(deletedId)-message", conversationId: deletedId, sequence: 1, createdAt: 500)
            }
        }
        try context.save()

        let items = await repository.cachedConversationList()
        #expect(items.map(\.id) == ["visible"])
    }

    @Test
    func sortsByLatestLiveMessageOrCreationTimeWithStableTies() async throws {
        insertConversation(id: "old-active", createdAt: 100)
        insertMessage(id: "earlier", conversationId: "old-active", sequence: 1, createdAt: 200)
        insertMessage(id: "latest", conversationId: "old-active", sequence: 2, createdAt: 600)
        insertMessage(id: "deleted-latest", conversationId: "old-active", sequence: 3, createdAt: 900, deleted: true)
        insertConversation(id: "recent-quiet", createdAt: 400)
        insertMessage(id: "quiet", conversationId: "recent-quiet", sequence: 1, createdAt: 450)
        insertConversation(id: "b-empty", createdAt: 500)
        insertConversation(id: "a-empty", createdAt: 500)
        try context.save()

        let items = await repository.cachedConversationList()
        #expect(items.map(\.id) == ["old-active", "a-empty", "b-empty", "recent-quiet"])
        #expect(items.first?.lastMessagePreview == "message latest")
        #expect(items.first?.lastActivityAt == Date(timeIntervalSince1970: 600))
        #expect(items.first?.unreadCount == 2)
        let repeatedItems = await repository.cachedConversationList()
        #expect(repeatedItems == items)
    }

    private func insertConversation(
        id: String,
        type: String = "group",
        name: String? = nil,
        createdAt: TimeInterval,
    ) {
        context.insert(CachedConversation(
            id: id,
            socialGraphId: "graph-test",
            type: type,
            publicName: name ?? "Group \(id)",
            createdByActorId: "me",
            status: "active",
            createdAt: Date(timeIntervalSince1970: createdAt),
        ))
    }

    private func insertMessage(
        id: String,
        conversationId: String,
        sequence: Int,
        createdAt: TimeInterval,
        deleted: Bool = false,
    ) {
        context.insert(CachedMessage(
            id: id,
            conversationId: conversationId,
            senderActorId: "mira",
            sequence: sequence,
            clientIdempotencyKey: "key-\(id)",
            kind: "text",
            content: "message \(id)",
            structuredPayload: nil,
            replyToMessageId: nil,
            burstId: nil,
            status: "accepted",
            createdAt: Date(timeIntervalSince1970: createdAt),
            deletedAt: deleted ? Date(timeIntervalSince1970: createdAt + 1) : nil,
        ))
    }
}
