import Foundation

/// Handles importing app data from JSON backup
struct DataImporter {
    /// Import a backup, returning the count of restored items
    @discardableResult
    static func importBackup(
        from data: Data,
        configStore: APIConfigStore,
        localization: LocalizationManager,
        themeManager: ThemeManager,
        accentColorManager: AccentColorManager,
        appState: AppState,
        chatStore: ChatStore,
        affinityService: AffinityService,
        bookmarkService: BookmarkService,
        draftService: DraftService,
        momentsStore: MomentsStore,
        backgroundStore: BackgroundStore,
        userProfileStore: UserProfileStore,
        socialService: SocialService,
        friendService: FriendService,
        memoryService: MemoryService
    ) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppBackup.self, from: data)

        var count = 0

        // Restore all serialized blobs first so store-backed domains come back.
        if let raw = backup.storageData {
            try validateStorageData(raw, decoder: decoder)
            count += try StorageService.shared.importAllValidated(raw)
        }

        if let images = backup.momentsImages {
            count += try restoreMomentsImages(images)
        }

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
            if let completed = settings["hasCompletedOnboarding"] {
                appState.hasCompletedOnboarding = (completed == "true")
                count += 1
            }
        }

        reloadAllStores(
            configStore: configStore,
            accentColorManager: accentColorManager,
            chatStore: chatStore,
            affinityService: affinityService,
            bookmarkService: bookmarkService,
            draftService: draftService,
            momentsStore: momentsStore,
            backgroundStore: backgroundStore,
            userProfileStore: userProfileStore,
            socialService: socialService,
            friendService: friendService,
            memoryService: memoryService
        )

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
                // Validate JSON payload structure without coupling to private nested structs.
                _ = try JSONSerialization.jsonObject(with: blob)
            default:
                break
            }
        }
    }

    private static func restoreMomentsImages(_ images: [String: Data]) throws -> Int {
        let fileManager = FileManager.default
        let directory = MomentsStore.momentsDirectory()
        let existing = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in existing where !file.hasDirectoryPath {
            try? fileManager.removeItem(at: file)
        }

        var count = 0
        for (filename, data) in images {
            // Basic path traversal guard.
            let cleanName = filename.replacingOccurrences(of: "/", with: "_")
            let target = directory.appendingPathComponent(cleanName)
            try data.write(to: target, options: .atomic)
            count += 1
        }
        return count
    }

    private static func reloadAllStores(
        configStore: APIConfigStore,
        accentColorManager: AccentColorManager,
        chatStore: ChatStore,
        affinityService: AffinityService,
        bookmarkService: BookmarkService,
        draftService: DraftService,
        momentsStore: MomentsStore,
        backgroundStore: BackgroundStore,
        userProfileStore: UserProfileStore,
        socialService: SocialService,
        friendService: FriendService,
        memoryService: MemoryService
    ) {
        configStore.reloadFromStorage()
        accentColorManager.reloadFromStorage()
        chatStore.reloadFromStorage()
        affinityService.reloadFromStorage()
        bookmarkService.reloadFromStorage()
        draftService.reloadFromStorage()
        momentsStore.reloadFromStorage()
        backgroundStore.reloadFromStorage()
        userProfileStore.reloadFromStorage()
        socialService.reloadFromStorage()
        friendService.reloadFromStorage()
        memoryService.reloadFromStorage()
    }
}
