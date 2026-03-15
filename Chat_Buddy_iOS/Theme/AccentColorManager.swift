import SwiftUI

/// Preset accent colors matching web's accent color system
struct AccentPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let localizedKey: String
    let color: Color

    static let presets: [AccentPreset] = [
        AccentPreset(id: "default", name: "Default", localizedKey: "accent_default", color: .accentColor),
        AccentPreset(id: "coral", name: "Coral", localizedKey: "accent_coral", color: Color(hex: "FF6B6B")),
        AccentPreset(id: "lavender", name: "Lavender", localizedKey: "accent_lavender", color: Color(hex: "B794F4")),
        AccentPreset(id: "mint", name: "Mint", localizedKey: "accent_mint", color: Color(hex: "38D9A9")),
        AccentPreset(id: "sky", name: "Sky", localizedKey: "accent_sky", color: Color(hex: "4DABF7")),
        AccentPreset(id: "gold", name: "Gold", localizedKey: "accent_gold", color: Color(hex: "FFD43B")),
        AccentPreset(id: "rose", name: "Rose", localizedKey: "accent_rose", color: Color(hex: "F783AC")),
        AccentPreset(id: "indigo", name: "Indigo", localizedKey: "accent_indigo", color: Color(hex: "5C7CFA")),
        AccentPreset(id: "emerald", name: "Emerald", localizedKey: "accent_emerald", color: Color(hex: "51CF66")),
        AccentPreset(id: "amber", name: "Amber", localizedKey: "accent_amber", color: Color(hex: "FFA94D")),
    ]
}

@Observable
final class AccentColorManager {
    var selectedPresetId: String {
        didSet { persist() }
    }

    var customColorHex: String? {
        didSet { persist() }
    }

    /// The active accent color
    var currentColor: Color {
        if let hex = customColorHex {
            return Color(hex: hex)
        }
        return AccentPreset.presets.first { $0.id == selectedPresetId }?.color ?? .accentColor
    }

    /// Whether using a custom color (not a preset)
    var isCustom: Bool {
        customColorHex != nil
    }

    init() {
        let saved: AccentColorState? = StorageService.shared.get("accentColor")
        self.selectedPresetId = saved?.presetId ?? "default"
        self.customColorHex = saved?.customHex
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
