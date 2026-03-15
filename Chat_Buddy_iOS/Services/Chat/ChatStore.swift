import SwiftUI

private let kChatSessions = "chatSessions"

/// Observable store managing all chat sessions, persisted via StorageService.
/// Supports both 1v1 sessions and multi-persona group sessions.
@Observable final class ChatStore {
    private(set) var sessions: [ChatSession] = []

    init() {
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

    /// Returns an existing group session with exactly this set of personas (order-independent), if any.
    func existingGroupSession(for personaIds: [String]) -> ChatSession? {
        let sorted = Set(personaIds)
        return sessions.first { $0.isGroup && Set($0.personaIds) == sorted }
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
