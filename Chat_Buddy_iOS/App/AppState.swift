import SwiftUI

@Observable
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet {
            StorageService.shared.set("hasCompletedOnboarding", value: hasCompletedOnboarding)
        }
    }

    var selectedTab: AppTab = .chats
    /// Non-isolated teardown on purpose — see `LegacyImporter.nonisolated deinit`.
    /// Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` this type gets an isolated
    /// deinit, so releasing it off the main actor frees the instance twice.
    nonisolated deinit {}

    init() {
        self.hasCompletedOnboarding = StorageService.shared.get("hasCompletedOnboarding", default: false)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }
}
