import SwiftUI

private let kChatSessions = "chatSessions"

/// Observable store managing all chat sessions, persisted via StorageService.
/// Supports both 1v1 sessions and multi-persona group sessions.
@Observable final class ChatStore {
    private(set) var sessions: [ChatSession] = []

    init() {
        sessions = StorageService.shared.get(kChatSessions, default: [])
    }

    /// Reload sessions from persisted storage.
    func reloadFromStorage() {
        sessions = StorageService.shared.get(kChatSessions, default: [])
    }

    // MARK: - 1v1 Session CRUD

    /// Returns the existing 1v1 session for a persona, or creates a new one.
    @discardableResult
    func getOrCreateSession(for personaId: String) -> ChatSession {
        if let existing = session(for: personaId) { return existing }
        let newSession = ChatSession(personaId: personaId)
        let insertIdx = sessions.firstIndex(where: { !$0.isPinned }) ?? sessions.count
        sessions.insert(newSession, at: insertIdx)
        save()
        return newSession
    }

    // MARK: - Group Session CRUD

    /// Creates a new group chat session with multiple personas.
    /// - Parameters:
    ///   - personaIds: Two or more persona IDs.
    ///   - groupName: Optional display name; defaults to the joined persona names.
    @discardableResult
    func createGroupSession(personaIds: [String], groupName: String? = nil) -> ChatSession {
        let newSession = ChatSession(personaIds: personaIds, groupName: groupName)
        let insertIdx = sessions.firstIndex(where: { !$0.isPinned }) ?? sessions.count
        sessions.insert(newSession, at: insertIdx)
        save()
        return newSession
    }

    /// Updates group display name for an existing session.
    func updateGroupName(id: String, name: String?) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].groupName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[idx].updatedAt = Date()
        save()
    }

    /// Updates session-level announcement for group chats.
    func updateAnnouncement(sessionId: String, announcement: GroupAnnouncement?) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].announcement = announcement
        sessions[idx].updatedAt = Date()
        save()
    }

    /// Updates group chat feature permissions.
    func updatePermissions(sessionId: String, permissions: ChatPermissions) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].permissions = permissions
        sessions[idx].updatedAt = Date()
        save()
    }

    /// Updates mute flag for a session.
    func updateMuted(sessionId: String, isMuted: Bool) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].isMuted = isMuted
        sessions[idx].updatedAt = Date()
        save()
    }

    /// Updates admin-only chat mode for a group session.
    func updateAdminOnly(sessionId: String, adminOnly: Bool) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].adminOnly = adminOnly
        sessions[idx].updatedAt = Date()
        save()
    }

    /// Updates a display nickname for a participant in a session.
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

    /// Adds one or more members into an existing group session.
    func addMembers(sessionId: String, personaIds: [String]) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let merged = Set(sessions[idx].personaIds).union(personaIds)
        sessions[idx].personaIds = Array(merged)
        sessions[idx].updatedAt = Date()
        save()
    }

    /// Returns an existing group session with exactly this set of personas (order-independent), if any.
    func existingGroupSession(for personaIds: [String]) -> ChatSession? {
        let sorted = Set(personaIds)
        return sessions.first { $0.isGroup && Set($0.personaIds) == sorted }
    }

    /// Creates a dedicated topic session for a single persona (used by Agent Workspace).
    @discardableResult
    func createTopicSession(for personaId: String, topicName: String?) -> ChatSession {
        let trimmed = topicName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSession = ChatSession(personaIds: [personaId], groupName: trimmed)
        let insertIdx = sessions.firstIndex(where: { !$0.isPinned }) ?? sessions.count
        sessions.insert(newSession, at: insertIdx)
        save()
        return newSession
    }

    // MARK: - General Lookup

    /// Finds a 1v1 session for a given persona.
    func session(for personaId: String) -> ChatSession? {
        sessions.first { !$0.isGroup && $0.primaryPersonaId == personaId }
    }

    func session(id: String) -> ChatSession? {
        sessions.first { $0.id == id }
    }

    // MARK: - Deletion

    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    // MARK: - Message Operations

    func appendMessage(_ message: ChatMessage, to sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.append(message)
        sessions[idx].updatedAt = Date()
        // Bubble to top of the appropriate group
        let updated = sessions.remove(at: idx)
        if updated.isPinned {
            sessions.insert(updated, at: 0)
        } else {
            let insertIdx = sessions.firstIndex(where: { !$0.isPinned }) ?? sessions.count
            sessions.insert(updated, at: insertIdx)
        }
        save()
    }

    /// Clears all conversation messages (preserves system prompts).
    func clearMessages(in sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.removeAll { $0.role != .system }
        sessions[idx].updatedAt = Date()
        save()
    }

    /// Deletes a single message by id within a session.
    func deleteMessage(id: String, in sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.removeAll { $0.id == id }
        sessions[idx].updatedAt = Date()
        save()
    }

    // MARK: - Polls

    /// Creates a new poll in a group session and returns it.
    @discardableResult
    func createPoll(
        in sessionId: String,
        question: String,
        options: [String],
        allowsMultipleSelection: Bool = false,
        isAnonymous: Bool = false,
        expiresInHours: Int? = nil
    ) -> ChatPoll? {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return nil }
        let cleanedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(10)
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

    /// Vote operation for a poll option. Returns whether vote succeeded.
    @discardableResult
    func votePoll(
        in sessionId: String,
        pollId: String,
        optionId: String,
        userId: String = "user-me"
    ) -> Bool {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return false }
        guard let pIdx = sessions[sIdx].polls.firstIndex(where: { $0.id == pollId }) else { return false }
        guard !sessions[sIdx].polls[pIdx].isExpired else { return false }
        guard let oIdx = sessions[sIdx].polls[pIdx].options.firstIndex(where: { $0.id == optionId }) else { return false }

        let poll = sessions[sIdx].polls[pIdx]

        if poll.allowsMultipleSelection {
            if sessions[sIdx].polls[pIdx].options[oIdx].votes.contains(userId) {
                sessions[sIdx].polls[pIdx].options[oIdx].votes.removeAll { $0 == userId }
            } else {
                sessions[sIdx].polls[pIdx].options[oIdx].votes.append(userId)
            }
        } else {
            for index in sessions[sIdx].polls[pIdx].options.indices {
                sessions[sIdx].polls[pIdx].options[index].votes.removeAll { $0 == userId }
            }
            sessions[sIdx].polls[pIdx].options[oIdx].votes.append(userId)
        }

        sessions[sIdx].updatedAt = Date()
        save()
        return true
    }

    // MARK: - Message Forwarding

    /// Forwards a message to one or more target sessions as a user-authored message.
    func forwardMessage(_ message: ChatMessage, to targetSessionIds: [String], sourceSessionId: String) {
        let uniqueTargets = Set(targetSessionIds.filter { $0 != sourceSessionId })
        guard !uniqueTargets.isEmpty else { return }

        for targetId in uniqueTargets {
            let forwarded = ChatMessage(
                role: .user,
                content: "[FORWARDED:\(message.id):\(sourceSessionId)]\n\(message.content)"
            )
            appendMessage(forwarded, to: targetId)
        }
    }

    // MARK: - Pin / Unpin

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

    // MARK: - Search

    func searchMessages(query: String, in sessionId: String) -> [ChatMessage] {
        guard !query.isEmpty,
              let session = sessions.first(where: { $0.id == sessionId }) else { return [] }
        let lowercased = query.lowercased()
        return session.displayMessages.filter { $0.content.lowercased().contains(lowercased) }
    }

    // MARK: - Persistence

    private func save() {
        StorageService.shared.set(kChatSessions, value: sessions)
    }

    /// Stable-sort: pinned sessions first (preserving relative updatedAt order within group).
    private func stableSort() {
        let pinned = sessions.filter { $0.isPinned }
        let unpinned = sessions.filter { !$0.isPinned }
        sessions = pinned + unpinned
    }
}
