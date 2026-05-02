import Foundation

@Observable final class UserProfileStore: StoreReloading {
    private(set) var profile: UserProfile = .default

    init() { load() }

    /// Reload profile from persisted storage.
    func reloadFromStorage() {
        load()
    }

    func update(nickName: String? = nil, avatarEmoji: String? = nil, signature: String? = nil) {
        if let n = nickName    { profile.nickName     = n }
        if let a = avatarEmoji { profile.avatarEmoji  = a }
        if let s = signature   { profile.signature    = s }
        save()
    }

    func updatePhotoAvatar(_ base64: String?) {
        profile.photoAvatarBase64 = base64
        save()
    }

    private func save() {
        StorageService.shared.set("userProfile", value: profile)
    }

    private func load() {
        if let saved: UserProfile = StorageService.shared.get("userProfile") {
            profile = saved
        }
    }
}
