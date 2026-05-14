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
        do {
            try KeychainService.set(Self.profileKeyKey(profile.id), value: activeConfig.apiKey, requireBiometric: false)
        } catch {
            print("Failed to save API key to keychain: \(error.localizedDescription)")
        }
        profiles.append(profile)
    }

    func loadProfile(_ profile: APIProfile) {
        var config = profile.config
        do {
            config.apiKey = try KeychainService.get(Self.profileKeyKey(profile.id)) ?? ""
        } catch {
            print("Failed to load API key from keychain: \(error.localizedDescription)")
            config.apiKey = ""
        }
        activeConfig = config
    }

    func deleteProfile(_ profile: APIProfile) {
        do {
            try KeychainService.delete(Self.profileKeyKey(profile.id))
        } catch {
            print("Failed to delete API key from keychain: \(error.localizedDescription)")
        }
        profiles.removeAll { $0.id == profile.id }
    }

    func deleteProfile(at offsets: IndexSet) {
        for index in offsets {
            do {
                try KeychainService.delete(Self.profileKeyKey(profiles[index].id))
            } catch {
                print("Failed to delete API key from keychain: \(error.localizedDescription)")
            }
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
        do {
            config.apiKey = try KeychainService.get(activeKeyKey) ?? ""
        } catch {
            print("Failed to load API key from keychain: \(error.localizedDescription)")
            config.apiKey = ""
        }

        var savedProfiles = storage.get("apiProfiles", default: [APIProfile]())
        for i in savedProfiles.indices {
            do {
                savedProfiles[i].config.apiKey = try KeychainService.get(profileKeyKey(savedProfiles[i].id)) ?? ""
            } catch {
                print("Failed to load profile API key from keychain: \(error.localizedDescription)")
                savedProfiles[i].config.apiKey = ""
            }
        }
        return (config, savedProfiles)
    }

    private func persistConfig() {
        storage.set("apiConfig", value: activeConfig)
        do {
            try KeychainService.set(Self.activeKeyKey, value: activeConfig.apiKey)
        } catch {
            print("Failed to save API key to keychain: \(error.localizedDescription)")
        }
    }

    private func persistProfiles() {
        storage.set("apiProfiles", value: profiles)
    }
}
