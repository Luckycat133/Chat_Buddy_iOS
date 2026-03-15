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
    @State private var memoryService = MemoryService()
    @State private var toolExecutorService = ToolExecutorService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // NOTE: BGTask registration must happen before the first scene connects.
        // The stores are created above with default values; the registration captures
        // them lazily via the handlers, so this is fine.
        // Info.plist must include BGTaskSchedulerPermittedIdentifiers with both keys.
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
            .environment(memoryService)
            .environment(toolExecutorService)
            .tint(accentColorManager.currentColor)
            .preferredColorScheme(themeManager.resolvedColorScheme)
            // Register and schedule BGTasks after stores are accessible
            .onAppear {
                MomentsBackgroundScheduler.register(
                    momentsStore: momentsStore,
                    apiConfigStore: apiConfigStore
                )
            }
            // Schedule next BGTask invocations when app moves to background
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    MomentsBackgroundScheduler.scheduleAll()
                }
            }
        }
    }
}
