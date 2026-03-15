import SwiftUI

struct RootTabView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(localization.t(tab.title), systemImage: tab.icon, value: tab) {
                    switch tab {
                    case .dashboard:
                        DashboardView()
                    case .chats:
                        ChatsView()
                    case .moments:
                        MomentsView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
        }
    }
}
