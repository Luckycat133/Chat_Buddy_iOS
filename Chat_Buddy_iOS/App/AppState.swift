import SwiftUI

@Observable
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet {
            StorageService.shared.set("hasCompletedOnboarding", value: hasCompletedOnboarding)
        }
    }

    var selectedTab: AppTab = .dashboard

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
