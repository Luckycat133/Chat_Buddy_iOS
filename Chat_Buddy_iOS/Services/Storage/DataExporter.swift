import Foundation
import UniformTypeIdentifiers
import SwiftUI
import os.log

struct AppBackup: Codable {
    let version: String
    let exportDate: Date
    let storageData: [String: Data]?
    let momentsImages: [String: Data]?
    let apiConfig: APIConfig?
    let apiProfiles: [APIProfile]?
    let settings: [String: String]?
}

struct DataExporter {
    private static let logger = Logger(subsystem: "com.chatbuddy", category: "DataExporter")

    static func exportAll(configStore: APIConfigStore, includeSensitiveData: Bool = false) -> AppBackup {
        var sanitizedConfig: APIConfig?
        var sanitizedProfiles: [APIProfile]?
        
        if includeSensitiveData {
            sanitizedConfig = configStore.activeConfig
            sanitizedProfiles = configStore.profiles
        } else {
            sanitizedConfig = configStore.activeConfig.withoutApiKey
            sanitizedProfiles = configStore.profiles.map { $0.withoutApiKey }
        }
        
        return AppBackup(
            version: AppConstants.appVersion,
            exportDate: Date(),
            storageData: StorageService.shared.exportAll().filter { !$0.key.contains("apiConfig") && !$0.key.contains("apiProfiles") },
            momentsImages: exportMomentsImages(),
            apiConfig: sanitizedConfig,
            apiProfiles: sanitizedProfiles,
            settings: exportSettings()
        )
    }

    static func exportToData(configStore: APIConfigStore, includeSensitiveData: Bool = false) throws -> Data {
        let backup = exportAll(configStore: configStore, includeSensitiveData: includeSensitiveData)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
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
        settings["oledEnabled"] = String(describing: defaults.bool(forKey: UserDefaults.Keys.oledEnabled))
        if let anim = defaults.string(forKey: UserDefaults.Keys.animationIntensity) {
            settings["animationIntensity"] = anim
        }
        settings["hasCompletedOnboarding"] = String(describing: defaults.bool(forKey: UserDefaults.Keys.hasCompletedOnboarding))
        return settings
    }

    private static func exportMomentsImages() -> [String: Data]? {
        let directory = MomentsStore.momentsDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Could not read moments directory for export")
            return nil
        }

        var result: [String: Data] = [:]
        for url in urls where !url.hasDirectoryPath {
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                result[url.lastPathComponent] = data
            } catch {
                logger.error("Failed to read moments image \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result.isEmpty ? nil : result
    }
}

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
