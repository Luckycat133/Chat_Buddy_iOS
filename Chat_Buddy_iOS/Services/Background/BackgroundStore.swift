import Foundation

@Observable final class BackgroundStore {
    private(set) var globalPresetId: String = "none"
    private(set) var globalAnimation: AnimatedBackground = .none
    private(set) var chatPresets: [String: String] = [:]          // sessionId → presetId
    private(set) var chatAnimations: [String: AnimatedBackground] = [:] // sessionId → animation

    init() { load() }

    // MARK: - Resolve

    func resolvedPreset(for sessionId: String) -> ChatBackgroundPreset {
        let id = chatPresets[sessionId] ?? globalPresetId
        return ChatBackgroundPreset.preset(id: id)
    }

    func resolvedAnimation(for sessionId: String) -> AnimatedBackground {
        chatAnimations[sessionId] ?? globalAnimation
    }

    // MARK: - Mutate (Global)

    func setGlobal(presetId: String) {
        globalPresetId = presetId
        save()
    }

    func setGlobalAnimation(_ animation: AnimatedBackground) {
        globalAnimation = animation
        save()
    }

    // MARK: - Mutate (Per-Chat)

    func setChat(sessionId: String, presetId: String) {
        if presetId == globalPresetId {
            chatPresets.removeValue(forKey: sessionId)
        } else {
            chatPresets[sessionId] = presetId
        }
        save()
    }

    func setChatAnimation(sessionId: String, animation: AnimatedBackground) {
        if animation == globalAnimation {
            chatAnimations.removeValue(forKey: sessionId)
        } else {
            chatAnimations[sessionId] = animation
        }
        save()
    }

    func clearChat(sessionId: String) {
        chatPresets.removeValue(forKey: sessionId)
        chatAnimations.removeValue(forKey: sessionId)
        save()
    }

    // MARK: - Persistence

    private struct StorageData: Codable {
        var globalPresetId: String
        var globalAnimationRaw: String
        var chatPresets: [String: String]
        var chatAnimationsRaw: [String: String]
    }

    private func save() {
        StorageService.shared.set(
            "backgrounds",
            value: StorageData(
                globalPresetId: globalPresetId,
                globalAnimationRaw: globalAnimation.rawValue,
                chatPresets: chatPresets,
                chatAnimationsRaw: chatAnimations.reduce(into: [:]) { $0[$1.key] = $1.value.rawValue }
            )
        )
    }

    private func load() {
        guard let data: StorageData = StorageService.shared.get("backgrounds") else { return }
        globalPresetId = data.globalPresetId
        globalAnimation = AnimatedBackground(rawValue: data.globalAnimationRaw) ?? .none
        chatPresets = data.chatPresets
        chatAnimations = data.chatAnimationsRaw.compactMapValues { AnimatedBackground(rawValue: $0) }
    }
}
