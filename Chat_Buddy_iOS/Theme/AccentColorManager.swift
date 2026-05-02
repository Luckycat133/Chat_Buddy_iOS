import SwiftUI

struct AccentPreset: Identifiable, Equatable {
    let id: String
    let localizedKey: String
    let color: Color

    static let presets: [AccentPreset] = [
        AccentPreset(id: "default", localizedKey: "accent_default", color: Color(hex: "007AFF")),
        AccentPreset(id: "coral", localizedKey: "accent_coral", color: Color(hex: "FF6B6B")),
        AccentPreset(id: "lavender", localizedKey: "accent_lavender", color: Color(hex: "B794F4")),
        AccentPreset(id: "mint", localizedKey: "accent_mint", color: Color(hex: "38D9A9")),
        AccentPreset(id: "sky", localizedKey: "accent_sky", color: Color(hex: "4DABF7")),
        AccentPreset(id: "gold", localizedKey: "accent_gold", color: Color(hex: "FFD43B")),
        AccentPreset(id: "rose", localizedKey: "accent_rose", color: Color(hex: "F783AC")),
        AccentPreset(id: "indigo", localizedKey: "accent_indigo", color: Color(hex: "5C7CFA")),
        AccentPreset(id: "emerald", localizedKey: "accent_emerald", color: Color(hex: "51CF66")),
        AccentPreset(id: "amber", localizedKey: "accent_amber", color: Color(hex: "FFA94D")),
    ]

    private static let presetMap: [String: AccentPreset] = {
        Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
    }()

    static func preset(for id: String) -> AccentPreset? {
        presetMap[id]
    }
}

@Observable
final class AccentColorManager {
    var selectedPresetId: String {
        didSet { persist() }
    }

    var customColorHex: String? {
        didSet { persist() }
    }

    var currentColor: Color {
        if let hex = customColorHex {
            return Color(hex: hex)
        }
        return AccentPreset.preset(for: selectedPresetId)?.color ?? Color(hex: "007AFF")
    }

    var isCustom: Bool {
        customColorHex != nil
    }

    init() {
        let saved: AccentColorState? = StorageService.shared.get("accentColor")
        self.selectedPresetId = saved?.presetId ?? "default"
        self.customColorHex = saved?.customHex
    }

    func reloadFromStorage() {
        let saved: AccentColorState? = StorageService.shared.get("accentColor")
        selectedPresetId = saved?.presetId ?? "default"
        customColorHex = saved?.customHex
    }

    func selectPreset(_ preset: AccentPreset) {
        selectedPresetId = preset.id
        customColorHex = nil
    }

    func setCustomColor(_ color: Color) {
        customColorHex = color.hexString
        selectedPresetId = "custom"
    }

    func reset() {
        selectedPresetId = "default"
        customColorHex = nil
    }

    private func persist() {
        let state = AccentColorState(presetId: selectedPresetId, customHex: customColorHex)
        StorageService.shared.set("accentColor", value: state)
    }
}

private struct AccentColorState: Codable {
    let presetId: String
    let customHex: String?
}
