import Foundation

/// Observable store for bookmarked messages, persisted via UserDefaults
@Observable final class BookmarkService {
    private(set) var bookmarks: [Bookmark] = []
    private static let key = "chat-buddy:bookmarks"

    init() {
        bookmarks = StorageService.shared.get(Self.key, default: [])
    }

    func isBookmarked(_ messageId: String) -> Bool {
        bookmarks.contains { $0.messageId == messageId }
    }

    func toggleBookmark(_ message: ChatMessage, sessionId: String, personaId: String) {
        if let idx = bookmarks.firstIndex(where: { $0.messageId == message.id }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.append(Bookmark(
                messageId: message.id,
                sessionId: sessionId,
                content: message.content,
                personaId: personaId
            ))
        }
        save()
    }

    func removeBookmark(messageId: String) {
        bookmarks.removeAll { $0.messageId == messageId }
        save()
    }

    func clear() {
        bookmarks.removeAll()
        save()
    }

    private func save() {
        StorageService.shared.set(Self.key, value: bookmarks)
    }
}
