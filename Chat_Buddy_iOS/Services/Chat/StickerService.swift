import SwiftUI

/// Sticker system with preset packs, AI persona-specific stickers, favorites, and recents.
/// Port of StickerModule from web version.
@Observable final class StickerService {

    // MARK: - Types

    struct StickerPack: Identifiable {
        let id: String
        let name: String
        let nameZh: String
        let stickers: [String]  // emoji characters
    }

    struct AISticker: Identifiable {
        var id: String { personaId }
        let personaId: String
        let stickers: [String]
    }

    // MARK: - Presets

    static let packs: [StickerPack] = [
        StickerPack(id: "emotions", name: "Emotions", nameZh: "表情", stickers: ["😊", "😂", "🥺", "😍", "😭", "😤", "🤔", "😴", "🤗", "🙄", "😏", "🥳"]),
        StickerPack(id: "actions", name: "Actions", nameZh: "动作", stickers: ["👋", "👍", "👎", "👏", "🙏", "🤝", "✌️", "🤞", "💪", "🙌", "👊", "❤️"]),
        StickerPack(id: "animals", name: "Animals", nameZh: "动物", stickers: ["🐱", "🐶", "🐰", "🐼", "🦊", "🐸", "🦋", "🐧", "🐻", "🐯", "🦁", "🐲"]),
        StickerPack(id: "food", name: "Food", nameZh: "美食", stickers: ["🍕", "🍜", "🍣", "🍔", "🍰", "🍩", "🍿", "🧋", "🍓", "🍦", "☕", "🍺"]),
    ]

    static let aiStickers: [AISticker] = [
        AISticker(personaId: "ai-miku", stickers: ["🎤", "🥬", "⭐", "🎵", "💙", "💃"]),
        AISticker(personaId: "ai-rem", stickers: ["💙", "🧹", "🍰", "🌸", "👹", "😴"]),
        AISticker(personaId: "ai-naruto", stickers: ["🍜", "🔥", "🐸", "🍃", "👊", "📜"]),
        AISticker(personaId: "ai-l", stickers: ["🍰", "☕", "🤔", "🔍", "🧊", "⛓️"]),
        AISticker(personaId: "ai-zerotwo", stickers: ["🍯", "💕", "🦕", "😈", "✈️", "💋"]),
        AISticker(personaId: "ai-gojo", stickers: ["😎", "🙈", "👊", "🍡", "😂", "6️⃣"]),
    ]

    // MARK: - State

    var favorites: [String] = []
    var recents: [String] = []

    private static let maxFavorites = 50
    private static let maxRecents = 20
    private static let storageKey = "chat-buddy-stickers"

    private struct StorageData: Codable {
        var favorites: [String]
        var recents: [String]
    }

    // MARK: - Init

    init() {
        let saved: StorageData = StorageService.shared.get(Self.storageKey, default: StorageData(favorites: [], recents: []))
        favorites = saved.favorites
        recents = saved.recents
    }

    // MARK: - Public API

    func toggleFavorite(_ sticker: String) {
        if let idx = favorites.firstIndex(of: sticker) {
            favorites.remove(at: idx)
        } else if favorites.count < Self.maxFavorites {
            favorites.insert(sticker, at: 0)
        }
        save()
    }

    func isFavorite(_ sticker: String) -> Bool {
        favorites.contains(sticker)
    }

    func addRecent(_ sticker: String) {
        recents.removeAll { $0 == sticker }
        recents.insert(sticker, at: 0)
        if recents.count > Self.maxRecents {
            recents = Array(recents.prefix(Self.maxRecents))
        }
        save()
    }

    func aiStickers(for personaId: String) -> [String] {
        Self.aiStickers.first { $0.personaId == personaId }?.stickers ?? []
    }

    // MARK: - Persistence

    private func save() {
        StorageService.shared.set(Self.storageKey, value: StorageData(favorites: favorites, recents: recents))
    }
}
