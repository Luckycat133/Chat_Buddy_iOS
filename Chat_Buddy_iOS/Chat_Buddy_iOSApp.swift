//
//  Chat_Buddy_iOSApp.swift
//  Chat_Buddy_iOS
//
//  Created by Jack on 2026/2/22.
//

import SwiftUI
import BackgroundTasks

@main
struct Chat_Buddy_iOSApp: App {
    @State private var appState = AppState()
    @State private var localization = LocalizationManager()
    @State private var themeManager = ThemeManager()
    @State private var accentColorManager = AccentColorManager()
    @State private var apiConfigStore = APIConfigStore()
    @State private var chatStore = ChatStore()
    @State private var affinityService = AffinityService()
    @State private var bookmarkService = BookmarkService()
    @State private var draftService = DraftService()
    @State private var momentsStore = MomentsStore()
    @State private var backgroundStore = BackgroundStore()
    @State private var userProfileStore = UserProfileStore()
    @State private var socialService = SocialService()
    @State private var friendService = FriendService()
    @State private var memoryService = MemoryService()
    @State private var toolExecutorService = ToolExecutorService()
    @State private var notificationService = NotificationService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // BGTask registration should happen as early as possible.
        // Info.plist must include BGTaskSchedulerPermittedIdentifiers with both keys.
        MomentsBackgroundScheduler.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView()
                }
            }
            .environment(appState)
            .environment(localization)
            .environment(themeManager)
            .environment(accentColorManager)
            .environment(apiConfigStore)
            .environment(chatStore)
            .environment(affinityService)
            .environment(bookmarkService)
            .environment(draftService)
            .environment(momentsStore)
            .environment(backgroundStore)
            .environment(userProfileStore)
            .environment(socialService)
            .environment(friendService)
            .environment(memoryService)
            .environment(toolExecutorService)
            .environment(notificationService)
            .tint(accentColorManager.currentColor)
            .preferredColorScheme(themeManager.resolvedColorScheme)
            .onAppear {
                MomentsBackgroundScheduler.configure(
                    momentsStore: momentsStore,
                    apiConfigStore: apiConfigStore
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: MomentsBackgroundScheduler.momentsDataDidChange)) { _ in
                momentsStore.reloadFromStorage()
            }
            // Schedule next BGTask invocations when app moves to background
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    MomentsBackgroundScheduler.scheduleAll()
                } else if newPhase == .active {
                    momentsStore.reloadFromStorage()
                }
            }
        }
    }
}
