import Foundation

/// Persists per-session message drafts with automatic 7-day expiry
@Observable final class DraftService {
    private var drafts: [String: DraftEntry] = [:]
    private static let key = "chat-buddy:drafts"
    private static let expiryDays = 7

    struct DraftEntry: Codable {
        var text: String
        var savedAt: Date
        var quotedMessageId: String?
    }

    init() {
        let loaded: [String: DraftEntry] = StorageService.shared.get(Self.key, default: [:])
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.expiryDays, to: Date()) ?? Date()
        drafts = loaded.filter { $0.value.savedAt > cutoff }
    }

    func draft(for sessionId: String) -> DraftEntry? {
        drafts[sessionId]
    }

    func save(text: String, quotedMessageId: String?, for sessionId: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts.removeValue(forKey: sessionId)
        } else {
            drafts[sessionId] = DraftEntry(text: text, savedAt: Date(), quotedMessageId: quotedMessageId)
        }
        persist()
    }

    func clear(for sessionId: String) {
        drafts.removeValue(forKey: sessionId)
        persist()
    }

    private func persist() {
        StorageService.shared.set(Self.key, value: drafts)
    }
}
