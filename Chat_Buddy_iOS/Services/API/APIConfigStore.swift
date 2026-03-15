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

    init() {
        self.activeConfig = StorageService.shared.get("apiConfig", default: APIConfig.default)
        self.profiles = StorageService.shared.get("apiProfiles", default: [APIProfile]())
    }

    // MARK: - Profile CRUD

    func saveAsProfile(name: String) {
        let profile = APIProfile(name: name, config: activeConfig)
        profiles.append(profile)
    }

    func loadProfile(_ profile: APIProfile) {
        activeConfig = profile.config
    }

    func deleteProfile(_ profile: APIProfile) {
        profiles.removeAll { $0.id == profile.id }
    }

    func deleteProfile(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
    }

    // MARK: - Persistence

    private func persistConfig() {
        storage.set("apiConfig", value: activeConfig)
    }

    private func persistProfiles() {
        storage.set("apiProfiles", value: profiles)
    }
}
