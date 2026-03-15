import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// App backup structure for JSON export
struct AppBackup: Codable {
    let version: String
    let exportDate: Date
    let apiConfig: APIConfig?
    let apiProfiles: [APIProfile]?
    let settings: [String: String]?
}

/// Handles exporting app data to JSON
struct DataExporter {
    static func exportAll(configStore: APIConfigStore) -> AppBackup {
        AppBackup(
            version: AppConstants.appVersion,
            exportDate: Date(),
            apiConfig: configStore.activeConfig,
            apiProfiles: configStore.profiles,
            settings: exportSettings()
        )
    }

    static func exportToData(configStore: APIConfigStore) throws -> Data {
        let backup = exportAll(configStore: configStore)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    private static func exportSettings() -> [String: String] {
        var settings: [String: String] = [:]
        let defaults = UserDefaults.standard
        if let lang = defaults.string(forKey: UserDefaults.Keys.uiLanguage) {
            settings["uiLanguage"] = lang
        }
        if let aiLang = defaults.string(forKey: UserDefaults.Keys.aiLanguage) {
            settings["aiLanguage"] = aiLang
        }
        if let theme = defaults.string(forKey: UserDefaults.Keys.themeMode) {
            settings["themeMode"] = theme
        }
        settings["oledEnabled"] = defaults.bool(forKey: UserDefaults.Keys.oledEnabled) ? "true" : "false"
        if let anim = defaults.string(forKey: UserDefaults.Keys.animationIntensity) {
            settings["animationIntensity"] = anim
        }
        return settings
    }
}

/// Document type for the backup file
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
