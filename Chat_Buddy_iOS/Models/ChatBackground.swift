import SwiftUI

/// A gradient background preset for chat wallpaper
struct ChatBackgroundPreset: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let nameZh: String
    let startHex: String    // empty → no custom background (default)
    let endHex: String

    var isDefault: Bool { id == "none" }

    func gradient(opacity: Double = 0.55) -> LinearGradient? {
        guard !isDefault else { return nil }
        return LinearGradient(
            colors: [Color(hex: startHex).opacity(opacity), Color(hex: endHex).opacity(opacity)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Presets

    static let presets: [ChatBackgroundPreset] = [
        .init(id: "none",      name: "Default",   nameZh: "默认",   startHex: "",        endHex: ""),
        .init(id: "aurora",    name: "Aurora",    nameZh: "极光",   startHex: "#16213E", endHex: "#4A1942"),
        .init(id: "sunset",    name: "Sunset",    nameZh: "落日",   startHex: "#FF6B6B", endHex: "#FFD93D"),
        .init(id: "ocean",     name: "Ocean",     nameZh: "海洋",   startHex: "#0093E9", endHex: "#80D0C7"),
        .init(id: "rose",      name: "Rose",      nameZh: "蔷薇",   startHex: "#FEAC5E", endHex: "#C779D0"),
        .init(id: "forest",    name: "Forest",    nameZh: "森林",   startHex: "#134E5E", endHex: "#71B280"),
        .init(id: "midnight",  name: "Midnight",  nameZh: "午夜",   startHex: "#0F2027", endHex: "#2C5364"),
        .init(id: "sakura",    name: "Sakura",    nameZh: "樱花",   startHex: "#FFB7C5", endHex: "#FFC8DD"),
        .init(id: "golden",    name: "Golden",    nameZh: "金色",   startHex: "#F7971E", endHex: "#FFD200"),
        .init(id: "cosmos",    name: "Cosmos",    nameZh: "宇宙",   startHex: "#3C1053", endHex: "#091835"),
    ]

    static func preset(id: String) -> ChatBackgroundPreset {
        presets.first { $0.id == id } ?? presets[0]
    }
}
