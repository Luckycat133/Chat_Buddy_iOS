import SwiftUI

@Observable
final class APIConfigStore {
    var activeConfig: APIConfig {
        didSet { persistConfig() }
    }

    var profiles: [APIProfile] {
        didSet { persistProfiles() }
    }

    private let storage = StorageService.shared

    private static let activeKeyKey = "api-key-active"
    private static func profileKeyKey(_ id: UUID) -> String { "api-key-profile-\(id.uuidString)" }

    init() {
        let (config, savedProfiles) = Self.loadFromStorage(storage: StorageService.shared)
        self.activeConfig = config
        self.profiles = savedProfiles
    }

    func saveAsProfile(name: String) {
        let profile = APIProfile(name: name, config: activeConfig)
        KeychainService.set(Self.profileKeyKey(profile.id), value: activeConfig.apiKey)
        profiles.append(profile)
    }

    func loadProfile(_ profile: APIProfile) {
        var config = profile.config
        config.apiKey = KeychainService.get(Self.profileKeyKey(profile.id)) ?? ""
        activeConfig = config
    }

    func deleteProfile(_ profile: APIProfile) {
        KeychainService.delete(Self.profileKeyKey(profile.id))
        profiles.removeAll { $0.id == profile.id }
    }

    func deleteProfile(at offsets: IndexSet) {
        for index in offsets {
            KeychainService.delete(Self.profileKeyKey(profiles[index].id))
        }
        profiles.remove(atOffsets: offsets)
    }

    func reloadFromStorage() {
        let (config, savedProfiles) = Self.loadFromStorage(storage: storage)
        activeConfig = config
        profiles = savedProfiles
    }

    private static func loadFromStorage(storage: StorageService) -> (APIConfig, [APIProfile]) {
        var config = storage.get("apiConfig", default: APIConfig.default)
        config.apiKey = KeychainService.get(activeKeyKey) ?? ""

        var savedProfiles = storage.get("apiProfiles", default: [APIProfile]())
        for i in savedProfiles.indices {
            savedProfiles[i].config.apiKey = KeychainService.get(profileKeyKey(savedProfiles[i].id)) ?? ""
        }
        return (config, savedProfiles)
    }

    private func persistConfig() {
        storage.set("apiConfig", value: activeConfig)
        KeychainService.set(Self.activeKeyKey, value: activeConfig.apiKey)
    }

    private func persistProfiles() {
        storage.set("apiProfiles", value: profiles)
    }
}
