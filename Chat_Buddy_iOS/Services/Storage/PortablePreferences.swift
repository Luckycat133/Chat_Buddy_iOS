import Foundation

/// A portable preferences-only document, deliberately distinct from an app backup.
struct PortablePreferences: Codable, Equatable {
    static let identifier = "chat-buddy.preferences"
    static let keys: Set<String> = [
        "format", "version", "uiLanguage", "aiLanguage", "themeMode",
        "oledEnabled", "animationIntensity",
    ]
    let format: String
    let version: Int
    let uiLanguage: String
    let aiLanguage: AILanguage
    let themeMode: ThemeMode
    let oledEnabled: Bool
    let animationIntensity: AnimationIntensity

    init(localization: LocalizationManager, theme: ThemeManager) {
        format = Self.identifier
        version = 1
        uiLanguage = localization.uiLanguage == .zh ? "zh" : localization.uiLanguage.rawValue
        aiLanguage = localization.aiLanguage
        themeMode = theme.mode
        oledEnabled = theme.oledEnabled
        animationIntensity = theme.animationIntensity
    }

    static func decodeIfPresent(_ data: Data) throws -> PortablePreferences? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["format"] as? String == identifier, let object else { return nil }
        guard Set(object.keys) == keys else {
            throw DataImportError(message: "Unsupported portable preferences fields.")
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1, ["system", "en", "zh"].contains(result.uiLanguage) else {
            throw DataImportError(message: "Unsupported portable preferences version or language.")
        }
        return result
    }

    func apply(localization: LocalizationManager, theme: ThemeManager) {
        localization.uiLanguage = uiLanguage == "zh" ? .zh : (AppLanguage(rawValue: uiLanguage) ?? .system)
        localization.aiLanguage = aiLanguage
        theme.mode = themeMode
        theme.oledEnabled = oledEnabled
        theme.animationIntensity = animationIntensity
    }
}
