import Foundation

/// Handles importing app data from JSON backup
struct DataImporter {
    /// Import a backup, returning the count of restored items
    @discardableResult
    static func importBackup(
        from data: Data,
        configStore: APIConfigStore,
        localization: LocalizationManager,
        themeManager: ThemeManager
    ) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppBackup.self, from: data)

        var count = 0

        // Restore API config
        if let config = backup.apiConfig {
            configStore.activeConfig = config
            count += 1
        }

        // Restore profiles
        if let profiles = backup.apiProfiles {
            configStore.profiles = profiles
            count += profiles.count
        }

        // Restore settings
        if let settings = backup.settings {
            if let lang = settings["uiLanguage"], let appLang = AppLanguage(rawValue: lang) {
                localization.uiLanguage = appLang
                count += 1
            }
            if let aiLang = settings["aiLanguage"], let al = AILanguage(rawValue: aiLang) {
                localization.aiLanguage = al
                count += 1
            }
            if let mode = settings["themeMode"], let tm = ThemeMode(rawValue: mode) {
                themeManager.mode = tm
                count += 1
            }
            if let oled = settings["oledEnabled"] {
                themeManager.oledEnabled = oled == "true"
                count += 1
            }
            if let anim = settings["animationIntensity"], let ai = AnimationIntensity(rawValue: anim) {
                themeManager.animationIntensity = ai
                count += 1
            }
        }

        return count
    }
}
