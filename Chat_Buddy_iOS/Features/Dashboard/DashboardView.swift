import SwiftUI

struct DashboardView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(ThemeManager.self) private var themeManager
    @Environment(ChatStore.self) private var chatStore
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = DashboardViewModel()
    @State private var showFriends = false

    private var isEffectivelyDark: Bool {
        themeManager.mode == .dark || (themeManager.mode == .system && colorScheme == .dark)
    }

    private let columns = [
        GridItem(.flexible(), spacing: DSSpacing.sm),
        GridItem(.flexible(), spacing: DSSpacing.sm),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    greetingSection

                    LazyVGrid(columns: columns, spacing: DSSpacing.sm) {
                        RecentChatsWidget()
                        StatsWidget()
                        QuickActionsWidget(
                            onNewChat: { appState.selectedTab = .chats },
                            onFriends: { showFriends = true }
                        )
                        FriendsWidget()
                    }
                    .padding(.horizontal, DSSpacing.sm)

                    TodaysPickWidget(
                        persona: viewModel.todaysPick,
                        onTap: { appState.selectedTab = .chats }
                    )
                        .padding(.horizontal, DSSpacing.sm)

                    SocialWidget()
                        .padding(.horizontal, DSSpacing.sm)
                }
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.huge)
            }
            .navigationTitle(localization.t("nav_dashboard"))
            .sheet(isPresented: $showFriends) {
                NavigationStack { FriendsView() }
            }
            .background {
                if themeManager.oledEnabled && isEffectivelyDark {
                    Color.black.ignoresSafeArea()
                }
            }
        }
    }

    private var greetingSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(localization.t(viewModel.greetingKey))
                    .font(DSTypography.largeTitle)
                Text(viewModel.dateString)
                    .font(DSTypography.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: DSIconSize.xxl))
                .foregroundStyle(.tint.opacity(0.8))
        }
        .padding(.horizontal, DSSpacing.md)
    }
}
