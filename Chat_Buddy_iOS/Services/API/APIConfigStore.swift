import SwiftUI

/// Observable store for the active API configuration and saved profiles
@Observable
final class APIConfigStore {
    /// The currently active configuration
    var activeConfig: APIConfig {
        didSet { persistConfig() }
    }

    /// Saved provider profiles
    var profiles: [APIProfile] {
        didSet { persistProfiles() }
    }

    private let storage = StorageService.shared

    // MARK: - Keychain keys

    private static let activeKeyKey = "api-key-active"
    private static func profileKeyKey(_ id: UUID) -> String { "api-key-profile-\(id.uuidString)" }

    init() {
        var config = StorageService.shared.get("apiConfig", default: APIConfig.default)
        config.apiKey = KeychainService.get(Self.activeKeyKey) ?? ""
        self.activeConfig = config

        var savedProfiles = StorageService.shared.get("apiProfiles", default: [APIProfile]())
        for i in savedProfiles.indices {
            savedProfiles[i].config.apiKey = KeychainService.get(Self.profileKeyKey(savedProfiles[i].id)) ?? ""
        }
        self.profiles = savedProfiles
    }

    // MARK: - Profile CRUD

    func saveAsProfile(name: String) {
        let profile = APIProfile(name: name, config: activeConfig)
        KeychainService.set(Self.profileKeyKey(profile.id), value: activeConfig.apiKey)
        profiles.append(profile)
    }

    func loadProfile(_ profile: APIProfile) {
        activeConfig = profile.config
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

    /// Reload active config + profiles from persisted storage.
    /// Useful after importing a backup while the app is running.
    func reloadFromStorage() {
        var config = storage.get("apiConfig", default: APIConfig.default)
        config.apiKey = KeychainService.get(Self.activeKeyKey) ?? ""
        activeConfig = config

        var savedProfiles = storage.get("apiProfiles", default: [APIProfile]())
        for i in savedProfiles.indices {
            savedProfiles[i].config.apiKey = KeychainService.get(Self.profileKeyKey(savedProfiles[i].id)) ?? ""
        }
        profiles = savedProfiles
    }

    // MARK: - Persistence

    private func persistConfig() {
        // apiKey is deliberately excluded from UserDefaults (see APIConfig.CodingKeys)
        storage.set("apiConfig", value: activeConfig)
        KeychainService.set(Self.activeKeyKey, value: activeConfig.apiKey)
    }

    private func persistProfiles() {
        // Profiles are persisted without apiKeys; keys are in Keychain
        storage.set("apiProfiles", value: profiles)
    }
}
