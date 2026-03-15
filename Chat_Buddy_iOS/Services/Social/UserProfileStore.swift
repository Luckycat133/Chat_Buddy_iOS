import Foundation

@Observable final class UserProfileStore {
    private(set) var profile: UserProfile = .default

    init() { load() }

    func update(nickName: String? = nil, avatarEmoji: String? = nil, signature: String? = nil) {
        if let n = nickName    { profile.nickName     = n }
        if let a = avatarEmoji { profile.avatarEmoji  = a }
        if let s = signature   { profile.signature    = s }
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
