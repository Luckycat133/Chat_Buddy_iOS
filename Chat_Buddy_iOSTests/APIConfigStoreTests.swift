import XCTest
@testable import Chat_Buddy_iOS

final class APIConfigStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var storage: StorageService!
    private var store: APIConfigStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: #function)!
        storage = StorageService(defaults: defaults)
        defaults.removePersistentDomain(forName: #function)
        KeychainService.delete("api-key-active")
        store = TestableAPIConfigStore(storage: storage)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: #function)
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialActiveConfigIsDefault() {
        let freshStore = TestableAPIConfigStore(storage: storage)
        XCTAssertEqual(freshStore.activeConfig.baseURL, APIConfig.default.baseURL)
        XCTAssertEqual(freshStore.activeConfig.model, APIConfig.default.model)
    }

    func testInitialProfilesIsEmpty() {
        let freshStore = TestableAPIConfigStore(storage: storage)
        XCTAssertTrue(freshStore.profiles.isEmpty)
    }

    // MARK: - Config Persistence

    func testActiveConfigSavedToStorage() {
        store.activeConfig.model = "gpt-4"
        let loaded: APIConfig? = storage.get("apiConfig")
        XCTAssertEqual(loaded?.model, "gpt-4")
    }

    func testActiveConfigApiKeySavedToKeychain() {
        store.activeConfig.apiKey = "test-key-123"
        let keychainKey = "api-key-active"
        let saved = KeychainService.get(keychainKey)
        XCTAssertEqual(saved, "test-key-123")
    }

    func testActiveConfigReloadedFromStorage() {
        store.activeConfig.model = "gpt-4o"
        store.activeConfig.apiKey = "reload-test-key"
        let freshStore = TestableAPIConfigStore(storage: storage)
        XCTAssertEqual(freshStore.activeConfig.model, "gpt-4o")
        XCTAssertEqual(freshStore.activeConfig.apiKey, "reload-test-key")
    }

    // MARK: - Profile Management

    func testSaveAsProfileCreatesProfile() {
        store.activeConfig.model = "custom-model"
        store.activeConfig.apiKey = "profile-key"
        store.saveAsProfile(name: "My Profile")
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.name, "My Profile")
    }

    func testSaveAsProfileStoresApiKeyInKeychain() {
        store.activeConfig.apiKey = "secret-key"
        store.saveAsProfile(name: "Secure Profile")
        let keychainKey = "api-key-profile-\(store.profiles[0].id.uuidString)"
        let saved = KeychainService.get(keychainKey)
        XCTAssertEqual(saved, "secret-key")
    }

    func testSaveAsProfileDoesNotAffectActiveConfig() {
        let originalModel = store.activeConfig.model
        store.saveAsProfile(name: "New Profile")
        XCTAssertEqual(store.activeConfig.model, originalModel)
    }

    func testLoadProfileUpdatesActiveConfig() {
        store.activeConfig.model = "profile-model"
        store.activeConfig.apiKey = "original-key"
        store.saveAsProfile(name: "Test Profile")
        let profile = store.profiles[0]
        KeychainService.set("api-key-profile-\(profile.id.uuidString)", value: "loaded-key")
        store.activeConfig.apiKey = "changed-key"
        store.loadProfile(profile)
        XCTAssertEqual(store.activeConfig.model, "profile-model")
        XCTAssertEqual(store.activeConfig.apiKey, "loaded-key")
    }

    func testLoadProfileMergesCorrectly() {
        store.activeConfig = APIConfig(baseURL: "https://custom.com", apiKey: "old", model: "old-model", temperature: 0.5, timeout: 30, maxRetries: 2)
        store.saveAsProfile(name: "Custom")
        let profile = store.profiles[0]
        KeychainService.set("api-key-profile-\(profile.id.uuidString)", value: "profile-api-key")
        store.activeConfig.apiKey = "different"
        store.loadProfile(profile)
        XCTAssertEqual(store.activeConfig.baseURL, "https://custom.com")
        XCTAssertEqual(store.activeConfig.apiKey, "profile-api-key")
    }

    func testDeleteProfileRemovesFromList() {
        store.saveAsProfile(name: "To Delete")
        let profile = store.profiles[0]
        store.deleteProfile(profile)
        XCTAssertTrue(store.profiles.isEmpty)
    }

    func testDeleteProfileRemovesKeychainEntry() {
        store.saveAsProfile(name: "To Delete")
        let profile = store.profiles[0]
        let keychainKey = "api-key-profile-\(profile.id.uuidString)"
        _ = KeychainService.set(keychainKey, value: "sensitive")
        store.deleteProfile(profile)
        let remaining = KeychainService.get(keychainKey)
        XCTAssertNil(remaining)
    }

    func testDeleteProfileAtOffsets() {
        store.saveAsProfile(name: "First")
        store.saveAsProfile(name: "Second")
        store.deleteProfile(at: IndexSet(integer: 0))
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.name, "Second")
    }

    func testDeleteProfileAtOffsetsRemovesAllKeychainEntries() {
        store.saveAsProfile(name: "P1")
        store.saveAsProfile(name: "P2")
        let ids = store.profiles.map { $0.id.uuidString }
        store.deleteProfile(at: IndexSet(integersIn: 0..<2))
        for id in ids {
            let key = "api-key-profile-\(id)"
            XCTAssertNil(KeychainService.get(key))
        }
    }

    // MARK: - Reload from Storage

    func testReloadFromStorageRestoresState() {
        store.activeConfig.model = "reloaded-model"
        store.saveAsProfile(name: "Reload Profile")
        let profile = store.profiles[0]
        let freshStore = TestableAPIConfigStore(storage: storage)
        XCTAssertEqual(freshStore.activeConfig.model, "reloaded-model")
        XCTAssertEqual(freshStore.profiles.count, 1)
        XCTAssertEqual(freshStore.profiles.first?.name, "Reload Profile")
    }

    func testReloadFromStorageRestoresKeychainKeysForProfiles() {
        store.saveAsProfile(name: "Keychain Test")
        let profile = store.profiles[0]
        let keychainKey = "api-key-profile-\(profile.id.uuidString)"
        _ = KeychainService.set(keychainKey, value: "restored-key")
        let freshStore = TestableAPIConfigStore(storage: storage)
        XCTAssertEqual(freshStore.activeConfig.apiKey, "")
        XCTAssertEqual(freshStore.profiles.first?.config.apiKey, "restored-key")
    }

    // MARK: - Profile withoutApiKey

    func testProfileWithoutApiKeyMasksApiKey() {
        store.activeConfig.apiKey = "secret-api-key"
        store.saveAsProfile(name: "Masked Profile")
        let masked = store.profiles[0].withoutApiKey
        XCTAssertEqual(masked.config.apiKey, "")
    }

    func testProfileWithoutApiKeyPreservesOtherFields() {
        store.activeConfig.baseURL = "https://example.com"
        store.activeConfig.model = "example-model"
        store.saveAsProfile(name: "Preserve Profile")
        let masked = store.profiles[0].withoutApiKey
        XCTAssertEqual(masked.config.baseURL, "https://example.com")
        XCTAssertEqual(masked.config.model, "example-model")
    }
}

// MARK: - Testable Subclass

final class TestableAPIConfigStore {
    var activeConfig: APIConfig
    var profiles: [APIProfile]
    private let storage: StorageService

    private static let activeKeyKey = "api-key-active"
    private static func profileKeyKey(_ id: UUID) -> String { "api-key-profile-\(id.uuidString)" }

    init(storage: StorageService) {
        self.storage = storage
        var config = storage.get("apiConfig", default: APIConfig.default)
        config.apiKey = KeychainService.get(Self.activeKeyKey) ?? ""
        var savedProfiles = storage.get("apiProfiles", default: [APIProfile]())
        for i in savedProfiles.indices {
            savedProfiles[i].config.apiKey = KeychainService.get(Self.profileKeyKey(savedProfiles[i].id)) ?? ""
        }
        self.activeConfig = config
        self.profiles = savedProfiles
    }

    func saveAsProfile(name: String) {
        let profile = APIProfile(name: name, config: activeConfig)
        KeychainService.set(Self.profileKeyKey(profile.id), value: activeConfig.apiKey)
        profiles.append(profile)
        persistProfiles()
    }

    func loadProfile(_ profile: APIProfile) {
        var config = profile.config
        config.apiKey = KeychainService.get(Self.profileKeyKey(profile.id)) ?? ""
        activeConfig = config
    }

    func deleteProfile(_ profile: APIProfile) {
        KeychainService.delete(Self.profileKeyKey(profile.id))
        profiles.removeAll { $0.id == profile.id }
        persistProfiles()
    }

    func deleteProfile(at offsets: IndexSet) {
        for index in offsets {
            KeychainService.delete(Self.profileKeyKey(profiles[index].id))
        }
        profiles.remove(atOffsets: offsets)
        persistProfiles()
    }

    private func persistProfiles() {
        storage.set("apiProfiles", value: profiles)
    }
}
