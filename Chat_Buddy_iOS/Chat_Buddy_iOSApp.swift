//
//  Chat_Buddy_iOSApp.swift
//  Chat_Buddy_iOS
//
//  Created by Jack on 2026/2/22.
//

import SwiftUI
import BackgroundTasks
import os

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

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ChatBuddy",
        category: "App"
    )

    init() {
        // BGTask registration should happen as early as possible.
        // Info.plist must include BGTaskSchedulerPermittedIdentifiers with both keys.
        do {
            try MomentsBackgroundScheduler.register()
        } catch {
            logger.error("BGTask registration failed: \(error.localizedDescription, privacy: .public)")
        }
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
            .task {
                // .task runs once on first appearance and is cancelled if the
                // view goes away — better than .onAppear for one-shot wiring.
                MomentsBackgroundScheduler.configure(
                    momentsStore: momentsStore,
                    apiConfigStore: apiConfigStore
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: MomentsBackgroundScheduler.momentsDataDidChange)) { _ in
                momentsStore.reloadFromStorage()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            MomentsBackgroundScheduler.scheduleAll()
        case .active:
            momentsStore.reloadFromStorage()
        case .inactive:
            break
        @unknown default:
            logger.warning("Unknown scene phase: \(String(describing: newPhase), privacy: .public)")
        }
    }
}
