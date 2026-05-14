import XCTest
@testable import Chat_Buddy_iOS

@MainActor
final class ChatStoreTests: XCTestCase {

    private var store: ChatStore!
    private var mockDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mockDefaults = UserDefaults(suiteName: #function)!
        let storage = StorageService(defaults: mockDefaults)
        mockDefaults.removeObject(forKey: "chat-buddy:chatSessions")
    }

    override func tearDown() {
        mockDefaults.removeObject(forKey: "chat-buddy:chatSessions")
        mockDefaults.removePersistentDomain(forName: #function)
        super.tearDown()
    }

    // MARK: - Session CRUD

    func testGetOrCreateSessionCreatesNew() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        XCTAssertEqual(session.personaIds, ["persona-1"])
        XCTAssertFalse(session.id.isEmpty)
    }

    func testGetOrCreateSessionReturnsExisting() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let first = store.getOrCreateSession(for: "persona-1")
        let second = store.getOrCreateSession(for: "persona-1")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testGetOrCreateSessionMultiplePersonas() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        _ = store.getOrCreateSession(for: "persona-1")
        _ = store.getOrCreateSession(for: "persona-2")
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testCreateGroupSession() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.createGroupSession(personaIds: ["alice", "bob"])
        XCTAssertTrue(session.isGroup)
        XCTAssertEqual(session.personaIds, ["alice", "bob"])
    }

    func testCreateGroupSessionWithName() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.createGroupSession(personaIds: ["alice", "bob"], groupName: "Team Chat")
        XCTAssertEqual(session.groupName, "Team Chat")
    }

    func testDeleteSession() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.deleteSession(session)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testDeleteSessionNotFound() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let fake = ChatSession(personaId: "ghost")
        store.deleteSession(fake)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    // MARK: - Message Operations

    func testAppendMessage() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let message = ChatMessage(role: .user, content: "Hello")
        store.appendMessage(message, to: session.id)
        let updated = store.session(id: session.id)
        XCTAssertEqual(updated?.messages.count, 1)
        XCTAssertEqual(updated?.messages.first?.content, "Hello")
    }

    func testAppendMessageSessionNotFound() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let message = ChatMessage(role: .user, content: "Hello")
        store.appendMessage(message, to: "nonexistent-id")
        XCTAssertTrue(store.sessions.allSatisfy { $0.messages.isEmpty })
    }

    func testDeleteMessage() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let message = ChatMessage(role: .user, content: "To be deleted")
        store.appendMessage(message, to: session.id)
        let msgId = store.session(id: session.id)!.messages.first!.id
        store.deleteMessage(id: msgId, in: session.id)
        XCTAssertTrue(store.session(id: session.id)!.messages.isEmpty)
    }

    func testDeleteMessageNotFound() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.deleteMessage(id: "ghost-message", in: session.id)
        XCTAssertTrue(store.sessions.allSatisfy { $0.messages.isEmpty })
    }

    func testClearMessages() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.appendMessage(ChatMessage(role: .user, content: "First"), to: session.id)
        store.appendMessage(ChatMessage(role: .assistant, content: "Second"), to: session.id)
        store.appendMessage(ChatMessage(role: .system, content: "System prompt"), to: session.id)
        store.clearMessages(in: session.id)
        let cleared = store.session(id: session.id)!
        XCTAssertEqual(cleared.messages.count, 1)
        XCTAssertEqual(cleared.messages.first?.role, .system)
    }

    // MARK: - Search

    func testSearchMessages() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.appendMessage(ChatMessage(role: .user, content: "Hello world"), to: session.id)
        store.appendMessage(ChatMessage(role: .assistant, content: "Hi there"), to: session.id)
        let results = store.searchMessages(query: "hello", in: session.id)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, "Hello world")
    }

    func testSearchMessagesCaseInsensitive() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.appendMessage(ChatMessage(role: .user, content: "HELLO WORLD"), to: session.id)
        let results = store.searchMessages(query: "hello", in: session.id)
        XCTAssertEqual(results.count, 1)
    }

    func testSearchMessagesEmptyQuery() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.appendMessage(ChatMessage(role: .user, content: "Hello"), to: session.id)
        let results = store.searchMessages(query: "", in: session.id)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchMessagesSessionNotFound() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let results = store.searchMessages(query: "hello", in: "nonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchMessagesSystemMessagesExcluded() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.appendMessage(ChatMessage(role: .system, content: "System hello"), to: session.id)
        store.appendMessage(ChatMessage(role: .user, content: "User hello"), to: session.id)
        let results = store.searchMessages(query: "hello", in: session.id)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.role, .user)
    }

    // MARK: - Polls

    func testCreatePoll() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let poll = store.createPoll(
            in: session.id,
            question: "Favorite color?",
            options: ["Red", "Blue", "Green"]
        )
        XCTAssertNotNil(poll)
        XCTAssertEqual(poll?.question, "Favorite color?")
        XCTAssertEqual(poll?.options.count, 3)
    }

    func testCreatePollMinimumOptions() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let poll = store.createPoll(in: session.id, question: "Yes or No?", options: ["Yes", "No"])
        XCTAssertNotNil(poll)
        XCTAssertEqual(poll?.options.count, 2)
    }

    func testCreatePollTooFewOptions() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let poll = store.createPoll(in: session.id, question: "Which?", options: ["Only One"])
        XCTAssertNil(poll)
    }

    func testCreatePollEmptyQuestion() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let poll = store.createPoll(in: session.id, question: "   ", options: ["A", "B"])
        XCTAssertNil(poll)
    }

    func testCreatePollTrimsOptions() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let poll = store.createPoll(
            in: session.id,
            question: "Which?",
            options: ["  Red  ", " Blue ", "Green"]
        )
        XCTAssertEqual(poll?.options.map { $0.text }, ["Red", "Blue", "Green"])
    }

    func testVotePollSingleSelection() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let poll = store.createPoll(in: session.id, question: "Yes or No?", options: ["Yes", "No"])!
        let optionId = poll.options[0].id
        let success = store.votePoll(in: session.id, pollId: poll.id, optionId: optionId)
        XCTAssertTrue(success)
        let updated = store.session(id: session.id)!.polls[0]
        XCTAssertTrue(updated.options[0].voterIds.contains("user-me"))
    }

    func testVotePollMultipleSelection() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let poll = store.createPoll(
            in: session.id,
            question: "Which colors?",
            options: ["Red", "Blue", "Green"],
            allowsMultipleSelection: true
        )!
        store.votePoll(in: session.id, pollId: poll.id, optionId: poll.options[0].id)
        store.votePoll(in: session.id, pollId: poll.id, optionId: poll.options[2].id)
        let updated = store.session(id: session.id)!.polls[0]
        XCTAssertEqual(updated.options.filter { $0.voterIds.contains("user-me") }.count, 2)
    }

    func testVotePollSingleDeselectsPrevious() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        let poll = store.createPoll(
            in: session.id,
            question: "Yes or No?",
            options: ["Yes", "No"]
        )!
        store.votePoll(in: session.id, pollId: poll.id, optionId: poll.options[0].id)
        store.votePoll(in: session.id, pollId: poll.id, optionId: poll.options[1].id)
        let updated = store.session(id: session.id)!.polls[0]
        XCTAssertFalse(updated.options[0].voterIds.contains("user-me"))
        XCTAssertTrue(updated.options[1].voterIds.contains("user-me"))
    }

    func testVotePollSessionNotFound() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let success = store.votePoll(in: "ghost", pollId: "poll", optionId: "option")
        XCTAssertFalse(success)
    }

    // MARK: - Group Management

    func testAddMembers() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.createGroupSession(personaIds: ["alice", "bob"])
        store.addMembers(sessionId: session.id, personaIds: ["charlie"])
        let updated = store.session(id: session.id)!
        XCTAssertTrue(updated.personaIds.contains("charlie"))
    }

    func testUpdateGroupName() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.createGroupSession(personaIds: ["alice", "bob"])
        store.updateGroupName(id: session.id, name: "New Name")
        XCTAssertEqual(store.session(id: session.id)?.groupName, "New Name")
    }

    func testUpdateGroupNameTrimsWhitespace() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.createGroupSession(personaIds: ["alice", "bob"])
        store.updateGroupName(id: session.id, name: "  Trimmed  ")
        XCTAssertEqual(store.session(id: session.id)?.groupName, "Trimmed")
    }

    func testUpdateMuted() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        XCTAssertFalse(session.isMuted)
        store.updateMuted(sessionId: session.id, isMuted: true)
        XCTAssertTrue(store.session(id: session.id)!.isMuted)
    }

    func testUpdateNickname() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.updateNickname(sessionId: session.id, participantId: "persona-1", nickname: "Buddy")
        XCTAssertEqual(store.session(id: session.id)!.nicknames["persona-1"], "Buddy")
    }

    func testUpdateNicknameRemovesEmpty() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.updateNickname(sessionId: session.id, participantId: "persona-1", nickname: nil)
        store.updateNickname(sessionId: session.id, participantId: "persona-1", nickname: "   ")
        XCTAssertNil(store.session(id: session.id)!.nicknames["persona-1"])
    }

    func testUpdateAdminOnly() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.createGroupSession(personaIds: ["alice", "bob"])
        XCTAssertFalse(session.adminOnly)
        store.updateAdminOnly(sessionId: session.id, adminOnly: true)
        XCTAssertTrue(store.session(id: session.id)!.adminOnly)
    }

    func testExistingGroupSession() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let first = store.createGroupSession(personaIds: ["alice", "bob"])
        let found = store.existingGroupSession(for: ["bob", "alice"])
        XCTAssertEqual(found?.id, first.id)
    }

    func testExistingGroupSessionNotFound() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        _ = store.createGroupSession(personaIds: ["alice", "bob"])
        let found = store.existingGroupSession(for: ["charlie"])
        XCTAssertNil(found)
    }

    // MARK: - Pin / Unpin

    func testPinSession() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.pinSession(id: session.id)
        XCTAssertTrue(store.session(id: session.id)!.isPinned)
        XCTAssertEqual(store.sessions.first?.id, session.id)
    }

    func testUnpinSession() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let session = store.getOrCreateSession(for: "persona-1")
        store.pinSession(id: session.id)
        store.unpinSession(id: session.id)
        XCTAssertFalse(store.session(id: session.id)!.isPinned)
    }

    func testPinnedSessionsStayFirst() {
        let storage = StorageService(defaults: mockDefaults)
        let store = TestableChatStore(storage: storage)
        let s1 = store.getOrCreateSession(for: "persona-1")
        let s2 = store.getOrCreateSession(for: "persona-2")
        store.pinSession(id: s1.id)
        store.pinSession(id: s2.id)
        XCTAssertEqual(store.sessions[0].id, s1.id)
        XCTAssertEqual(store.sessions[1].id, s2.id)
    }
}

// MARK: - Testable Subclass

@MainActor @Observable
final class TestableChatStore: StoreReloading {
    private(set) var sessions: [ChatSession] = []
    private let storage: StorageService

    init(storage: StorageService) {
        self.storage = storage
        reloadFromStorage()
    }

    func reloadFromStorage() {
        sessions = storage.get("chatSessions", default: [])
    }

    func getOrCreateSession(for personaId: String) -> ChatSession {
        if let existing = sessions.first(where: { !$0.isGroup && $0.primaryPersonaId == personaId }) {
            return existing
        }
        let newSession = ChatSession(personaId: personaId)
        let insertIdx = sessions.firstIndex(where: { !$0.isPinned }) ?? sessions.count
        sessions.insert(newSession, at: insertIdx)
        save()
        return newSession
    }

    func createGroupSession(personaIds: [String], groupName: String? = nil) -> ChatSession {
        let newSession = ChatSession(personaIds: personaIds, groupName: groupName)
        let insertIdx = sessions.firstIndex(where: { !$0.isPinned }) ?? sessions.count
        sessions.insert(newSession, at: insertIdx)
        save()
        return newSession
    }

    func deleteSession(_ session: ChatSession) {
        guard sessions.contains(where: { $0.id == session.id }) else { return }
        sessions.removeAll { $0.id == session.id }
        save()
    }

    func appendMessage(_ message: ChatMessage, to sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.append(message)
        sessions[idx].updatedAt = Date()
        let updated = sessions.remove(at: idx)
        let insertIdx = sessions.firstIndex(where: { !$0.isPinned }) ?? sessions.count
        sessions.insert(updated, at: insertIdx)
        save()
    }

    func deleteMessage(id: String, in sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.removeAll { $0.id == id }
        sessions[idx].updatedAt = Date()
        save()
    }

    func clearMessages(in sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.removeAll { $0.role != .system }
        sessions[idx].updatedAt = Date()
        save()
    }

    func searchMessages(query: String, in sessionId: String) -> [ChatMessage] {
        guard !query.isEmpty, let session = sessions.first(where: { $0.id == sessionId }) else { return [] }
        let lowercased = query.lowercased()
        return session.displayMessages.filter { $0.content.lowercased().contains(lowercased) }
    }

    func createPoll(in sessionId: String, question: String, options: [String], allowsMultipleSelection: Bool = false, isAnonymous: Bool = false, expiresInHours: Int? = nil) -> ChatPoll? {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return nil }
        let cleanedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(10)
        guard !cleanedQuestion.isEmpty, cleanedOptions.count >= 2 else { return nil }
        let poll = ChatPoll(
            question: cleanedQuestion,
            options: cleanedOptions.map { ChatPollOption(text: $0) },
            allowsMultipleSelection: allowsMultipleSelection,
            isAnonymous: isAnonymous,
            expiresAt: expiresInHours.map { Date().addingTimeInterval(Double($0) * 3600) }
        )
        sessions[idx].polls.insert(poll, at: 0)
        sessions[idx].updatedAt = Date()
        save()
        return poll
    }

    func votePoll(in sessionId: String, pollId: String, optionId: String, userId: String = "user-me") -> Bool {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return false }
        guard let pIdx = sessions[sIdx].polls.firstIndex(where: { $0.id == pollId }) else { return false }
        guard !sessions[sIdx].polls[pIdx].isExpired else { return false }
        guard let oIdx = sessions[sIdx].polls[pIdx].options.firstIndex(where: { $0.id == optionId }) else { return false }
        let poll = sessions[sIdx].polls[pIdx]
        if poll.allowsMultipleSelection {
            if sessions[sIdx].polls[pIdx].options[oIdx].voterIds.contains(userId) {
                sessions[sIdx].polls[pIdx].options[oIdx].voterIds.remove(userId)
            } else {
                sessions[sIdx].polls[pIdx].options[oIdx].voterIds.insert(userId)
            }
        } else {
            for index in sessions[sIdx].polls[pIdx].options.indices {
                sessions[sIdx].polls[pIdx].options[index].voterIds.remove(userId)
            }
            sessions[sIdx].polls[pIdx].options[oIdx].voterIds.insert(userId)
        }
        sessions[sIdx].updatedAt = Date()
        save()
        return true
    }

    func addMembers(sessionId: String, personaIds: [String]) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let merged = Set(sessions[idx].personaIds).union(personaIds)
        sessions[idx].personaIds = Array(merged)
        sessions[idx].updatedAt = Date()
        save()
    }

    func updateGroupName(id: String, name: String?) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].groupName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[idx].updatedAt = Date()
        save()
    }

    func updateMuted(sessionId: String, isMuted: Bool) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].isMuted = isMuted
        sessions[idx].updatedAt = Date()
        save()
    }

    func updateNickname(sessionId: String, participantId: String, nickname: String?) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        if let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            sessions[idx].nicknames[participantId] = trimmed
        } else {
            sessions[idx].nicknames.removeValue(forKey: participantId)
        }
        sessions[idx].updatedAt = Date()
        save()
    }

    func updateAdminOnly(sessionId: String, adminOnly: Bool) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].adminOnly = adminOnly
        sessions[idx].updatedAt = Date()
        save()
    }

    func existingGroupSession(for personaIds: [String]) -> ChatSession? {
        let sorted = Set(personaIds)
        return sessions.first { $0.isGroup && Set($0.personaIds) == sorted }
    }

    func pinSession(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = true
        stableSort()
        save()
    }

    func unpinSession(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = false
        stableSort()
        save()
    }

    func session(id: String) -> ChatSession? {
        sessions.first { $0.id == id }
    }

    private func save() {
        storage.setAsync("chatSessions", value: sessions)
    }

    private func stableSort() {
        let pinned = sessions.filter { $0.isPinned }
        let unpinned = sessions.filter { !$0.isPinned }
        sessions = pinned + unpinned
    }
}
