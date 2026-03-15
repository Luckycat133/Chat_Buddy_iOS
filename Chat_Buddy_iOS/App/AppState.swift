import SwiftUI

@Observable
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: UserDefaults.Keys.hasCompletedOnboarding)
        }
    }

    /// Currently selected root tab — mutate to programmatically switch tabs app-wide.
    var selectedTab: AppTab = .dashboard

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: UserDefaults.Keys.hasCompletedOnboarding)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }
}
