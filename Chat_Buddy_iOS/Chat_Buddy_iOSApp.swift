import SwiftUI
import BackgroundTasks
import SwiftData
import os

/// Cloud-first iOS app entry per `chat-buddy-ios-demo-development` skill.
///
///   - CloudAppState owns HTTP / Auth / Realtime / repositories / cache.
///   - The legacy AppState + ChatStore + MomentsStore remain available
///     for one-time legacy import; the legacy `MomentsBackgroundScheduler`
///     is wired as a no-op when `CBUseCloudRuntime` is true.
///   - Chats is the default tab per `IOS_IMPLEMENTATION.md` §6.
@main
struct Chat_Buddy_iOSApp: App {
    @State private var cloud: CloudAppState?
    @State private var cloudError: String?
    @State private var legacy = AppState()
    @State private var localization = LocalizationManager()
    @State private var themeManager = ThemeManager()
    @State private var accentColorManager = AccentColorManager()
    @State private var chatStore = ChatStore()
    @State private var momentsStore = MomentsStore()
    @State private var draftService = DraftService()
    @State private var knowledgeBaseStore = KnowledgeBaseStore()
    @State private var knowledgeGraphStore = KnowledgeGraphStore()
    @State private var useCloudRuntime: Bool = UserDefaults.standard
        .object(forKey: "CBUseCloudRuntime") as? Bool ?? true
    @Environment(\.scenePhase) private var scenePhase

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ChatBuddy",
        category: "App"
    )

    init() {
        PersonaStore.customPersonasProvider = { CustomPersonaStore.shared.customPersonas }
        if UserDefaults.standard.object(forKey: "CBUseCloudRuntime") == nil {
            UserDefaults.standard.set(true, forKey: "CBUseCloudRuntime")
        }
        do {
            try MomentsBackgroundScheduler.register()
        } catch {
            logger.error("BGTask registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var body: some Scene {
        WindowGroup {
            content
                .tint(accentColorManager.currentColor)
                .preferredColorScheme(themeManager.resolvedColorScheme)
                .task { await bootstrapCloudIfNeeded() }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if useCloudRuntime, let cloud {
            CloudAppRoot(cloud: cloud)
                .environmentObject(cloud)
                .environment(localization)
                .environment(themeManager)
                .environment(accentColorManager)
        } else {
            LegacyAppRoot(
                legacy: legacy,
                localization: localization,
                themeManager: themeManager,
                accentColorManager: accentColorManager,
                chatStore: chatStore,
                momentsStore: momentsStore,
                draftService: draftService,
                knowledgeBaseStore: knowledgeBaseStore,
                knowledgeGraphStore: knowledgeGraphStore,
                onSwitchToCloud: {
                    UserDefaults.standard.set(true, forKey: "CBUseCloudRuntime")
                    useCloudRuntime = true
                    Task { await bootstrapCloudIfNeeded() }
                },
            )
        }
    }

    private func bootstrapCloudIfNeeded() async {
        guard useCloudRuntime, cloud == nil else { return }
        do {
            let state = try CloudAppState()
            await state.bootstrap()
            self.cloud = state
            self.cloudError = nil
        } catch {
            logger.error("Cloud bootstrap failed: \(error.localizedDescription, privacy: .public)")
            self.cloudError = String(describing: error)
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            MomentsBackgroundScheduler.scheduleAll()
        case .active:
            if useCloudRuntime, let cloud {
                Task { await cloud.runInitialSync() }
            } else {
                momentsStore.reloadFromStorage()
            }
        case .inactive:
            break
        @unknown default:
            logger.warning("Unknown scene phase: \(String(describing: newPhase), privacy: .public)")
        }
    }
}

/// Cloud-first app root. Replaces the legacy `RootTabView` once the user is
/// authenticated and `cloud.stage == .ready`. While the cloud runtime boots
/// or the user is unauthenticated, shows `OnboardingChatView` (Mira) or a
/// dev-signin prompt.
///
/// Per `IOS_IMPLEMENTATION.md` §6: Chats is the default landing tab — the
/// legacy Dashboard tab is removed entirely.
private struct CloudAppRoot: View {
    @ObservedObject var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        switch cloud.stage {
        case .loading:
            ProgressView(localization.t("cloud_bootstrapping"))
        case .unauthenticated:
            DevSignInView(cloud: cloud)
        case .onboarding:
            OnboardingChatView()
                .environmentObject(cloud)
        case .ready, .offline:
            ChatsTabHost(cloud: cloud)
        }
    }
}

private struct ChatsTabHost: View {
    @ObservedObject var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        TabView(selection: $cloud.selectedTab) {
            ChatsRootView()
                .tabItem { Label(localization.t("nav_chats"), systemImage: "bubble.left.and.bubble.right") }
                .tag(CloudAppTab.chats)
            ContactsView()
                .tabItem { Label(localization.t("nav_contacts"), systemImage: "person.2") }
                .tag(CloudAppTab.contacts)
            CloudMomentsView()
                .tabItem { Label(localization.t("nav_moments"), systemImage: "globe") }
                .tag(CloudAppTab.moments)
            MeTabView(cloud: cloud)
                .tabItem { Label(localization.t("nav_settings"), systemImage: "person.crop.circle") }
                .tag(CloudAppTab.me)
        }
        .environmentObject(cloud)
    }
}

private struct DiagnosticsLink: View {
    @ObservedObject var cloud: CloudAppState

    var body: some View {
        NavigationLink("Diagnostics") {
            DiagnosticsView(cloud: cloud)
        }
    }
}

/// In-app diagnostics. Shows sync cursor, outbox count, environment,
/// auth state. Hidden by default in production builds (controlled by
/// `AppEnvironment.enableDiagnostics`); always visible in dev.
/// Internal so `MeTabView` (own file) can navigate to it.
struct DiagnosticsView: View {
    @ObservedObject var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        List {
            Section(localization.t("cloud_diag_env")) {
                LabeledContent(localization.t("cloud_diag_bundle"), value: cloud.environment.bundleIdentifier)
                LabeledContent(localization.t("cloud_diag_build"), value: cloud.environment.buildNumber)
                LabeledContent(localization.t("cloud_diag_apns"), value: cloud.environment.apnsEnvironment.rawValue)
                LabeledContent(localization.t("cloud_diag_api"), value: cloud.environment.apiBaseURL.absoluteString)
            }
            Section(localization.t("cloud_diag_health")) {
                Button(localization.t("cloud_diag_run")) {
                    Task { _ = try? await cloud.http.sendRaw(APIEndpoint(path: "/healthz")) }
                }
            }
        }
        .navigationTitle(localization.t("cloud_me_diagnostics_detail"))
    }
}

private struct DevSignInView: View {
    @ObservedObject var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var localization
    @State private var displayName: String = "Demo User"
    @State private var error: String?
    @State private var inFlight = false

    var body: some View {
        NavigationStack {
            Form {
                Section(localization.t("cloud_dev_signin_section")) {
                    TextField(localization.t("cloud_dev_signin_name"), text: $displayName)
                    Button {
                        Task { await signIn() }
                    } label: {
                        if inFlight { ProgressView() } else { Text(localization.t("cloud_dev_signin_action")) }
                    }
                    .disabled(inFlight)
                    Text(localization.t("cloud_dev_signin_note"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(localization.t("cloud_dev_signin_title"))
        }
    }

    private func signIn() async {
        inFlight = true
        defer { inFlight = false }
        do {
            try await cloud.devSignIn(displayName: displayName)
            self.error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct LegacyAppRoot: View {
    // These legacy stores use the Observation framework (@Observable), not
    // ObservableObject — plain properties are tracked automatically when read
    // in body; @ObservedObject requires ObservableObject conformance.
    var legacy: AppState
    var localization: LocalizationManager
    var themeManager: ThemeManager
    var accentColorManager: AccentColorManager
    var chatStore: ChatStore
    var momentsStore: MomentsStore
    var draftService: DraftService
    var knowledgeBaseStore: KnowledgeBaseStore
    var knowledgeGraphStore: KnowledgeGraphStore
    let onSwitchToCloud: () -> Void

    var body: some View {
        Group {
            if legacy.hasCompletedOnboarding {
                RootTabView()
                    .environment(legacy)
                    .environment(localization)
                    .environment(themeManager)
                    .environment(accentColorManager)
                    .environment(chatStore)
                    .environment(momentsStore)
                    .environment(draftService)
                    .environment(knowledgeBaseStore)
                    .environment(knowledgeGraphStore)
            } else {
                OnboardingView()
                    .environment(legacy)
                    .environment(localization)
                    .environment(themeManager)
                    .environment(accentColorManager)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Use cloud", action: onSwitchToCloud)
            }
        }
    }
}