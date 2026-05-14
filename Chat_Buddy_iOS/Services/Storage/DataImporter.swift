import Foundation

enum ImportCompatibility {
    case fullyCompatible
    case newerVersion(warning: String)
    case incompatibleVersion(error: String)
}

struct DataImportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static let missingVersion = DataImportError(message: "Backup file is missing a version identifier and cannot be safely imported.")
    static func incompatible(_ version: String, _ minSupported: String) -> DataImportError {
        DataImportError(message: "Backup version \(version) is older than the minimum supported version (\(minSupported)). Please update your backup or contact support.")
    }
}

protocol StoreReloading {
    func reloadFromStorage()
}

struct DataImporter {
    static let minimumSupportedVersion = "0.1.0"

    @discardableResult
    static func importBackup(
        from data: Data,
        configStore: APIConfigStore,
        localization: LocalizationManager,
        themeManager: ThemeManager,
        accentColorManager: AccentColorManager,
        appState: AppState,
        stores: [any StoreReloading]
    ) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppBackup.self, from: data)

        let compat = checkCompatibility(backup)
        switch compat {
        case .incompatibleVersion(let error):
            throw DataImportError(message: error)
        case .newerVersion, .fullyCompatible:
            break
        }

        var count = 0

        if let raw = backup.storageData {
            try validateStorageData(raw, decoder: decoder)
            count += try StorageService.shared.importAllValidated(raw)
        }

        if let images = backup.momentsImages {
            count += try restoreMomentsImages(images)
        }

        if let config = backup.apiConfig {
            configStore.activeConfig = config
            // 如果备份中包含 API 密钥，也保存到 Keychain
            if !config.apiKey.isEmpty {
                KeychainService.set(APIConfigStore.activeKeyKey, value: config.apiKey)
            }
            count += 1
        }

        if let profiles = backup.apiProfiles {
            configStore.profiles = profiles
            // 如果备份中包含 API 密钥，也保存到 Keychain
            for profile in profiles {
                if !profile.config.apiKey.isEmpty {
                    KeychainService.set(APIConfigStore.profileKeyKey(profile.id), value: profile.config.apiKey)
                }
            }
            count += profiles.count
        }

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
            if let completed = settings["hasCompletedOnboarding"] {
                appState.hasCompletedOnboarding = (completed == "true")
                count += 1
            }
        }

        for store in stores {
            store.reloadFromStorage()
        }
        PersonaStore.invalidateCache()

        return count
    }

    private static func validateStorageData(_ data: [String: Data], decoder: JSONDecoder) throws {
        for (key, blob) in data {
            guard StorageService.allowedImportKeys.contains(key) else {
                throw StorageService.ImportValidationError.keyNotAllowed(key)
            }
            guard blob.count <= StorageService.maxImportItemBytes else {
                throw StorageService.ImportValidationError.payloadTooLarge(
                    key: key,
                    size: blob.count,
                    max: StorageService.maxImportItemBytes
                )
            }
            switch key {
            case "apiConfig":
                _ = try decoder.decode(APIConfig.self, from: blob)
            case "apiProfiles":
                _ = try decoder.decode([APIProfile].self, from: blob)
            case "chatSessions":
                _ = try decoder.decode([ChatSession].self, from: blob)
            case "memories":
                _ = try decoder.decode(MemoriesData.self, from: blob)
            case "moments":
                _ = try decoder.decode(MomentsData.self, from: blob)
            case "personas.custom":
                _ = try decoder.decode([Persona].self, from: blob)
            case "social", "backgrounds", "bookmarks", "drafts", "userProfile", "accentColor", "intimacy",
                 "friends.groups", "friends.meta", "knowledgeBase", "knowledgeGraph.custom":
                _ = try JSONSerialization.jsonObject(with: blob)
            default:
                break
            }
        }
    }

    private static func restoreMomentsImages(_ images: [String: Data]) throws -> Int {
        let fileManager = FileManager.default
        let directory = MomentsStore.momentsDirectory()

        let tempDir = directory.appendingPathComponent("_import_tmp")
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var count = 0
        var success = true
        for (filename, data) in images {
            let safeName = URL(fileURLWithPath: filename).lastPathComponent
            guard !safeName.isEmpty else { continue }
            let target = tempDir.appendingPathComponent(safeName)
            do {
                try data.write(to: target, options: .atomic)
                count += 1
            } catch {
                success = false
            }
        }

        if success || count > 0 {
            let existing = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for file in existing where !file.hasDirectoryPath && file.lastPathComponent != "_import_tmp" {
                try? fileManager.removeItem(at: file)
            }

            let imported = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in imported {
                let dest = directory.appendingPathComponent(file.lastPathComponent)
                try? fileManager.moveItem(at: file, to: dest)
            }
            try? fileManager.removeItem(at: tempDir)
        } else {
            try? fileManager.removeItem(at: tempDir)
        }

        return count
    }

    private static func checkCompatibility(_ backup: AppBackup) -> ImportCompatibility {
        let version = backup.version

        guard !version.isEmpty else {
            return .incompatibleVersion(error: DataImportError.missingVersion.message)
        }

        let current = AppConstants.appVersion

        if version == current {
            return .fullyCompatible
        }

        if isVersion(version, olderThan: minimumSupportedVersion) {
            return .incompatibleVersion(
                error: DataImportError.incompatible(version, minimumSupportedVersion).message
            )
        }

        if isVersion(version, newerThan: current) {
            return .newerVersion(
                warning: "Backup was created with v\(version) which is newer than this app (v\(current)). Some data may not display correctly."
            )
        }

        return .fullyCompatible
    }

    private static func isVersion(_ version: String, olderThan minimum: String) -> Bool {
        compareVersions(version, minimum) == .orderedAscending
    }

    private static func isVersion(_ version: String, newerThan current: String) -> Bool {
        compareVersions(version, current) == .orderedDescending
    }

    private static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(aParts.count, bParts.count)
        for i in 0..<maxLen {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal != bVal { return aVal < bVal ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
