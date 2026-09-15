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
            CloudAppRoot(cloud: cloud, legacy: legacy)
                .environment(cloud)
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
    var legacy: AppState

    var body: some View {
        switch cloud.stage {
        case .loading:
            ProgressView("Bootstrapping…")
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
    @State private var selectedTab: CloudAppTab = .chats

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatsRootView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(CloudAppTab.chats)
            LegacyContactsTab()
                .tabItem { Label("Contacts", systemImage: "person.2") }
                .tag(CloudAppTab.contacts)
            LegacyMomentsTab()
                .tabItem { Label("Moments", systemImage: "globe") }
                .tag(CloudAppTab.moments)
            MeTab(cloud: cloud)
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
                .tag(CloudAppTab.me)
        }
        .environmentObject(cloud)
        .onChange(of: cloud.selectedTab) { _, newValue in
            selectedTab = newValue
        }
    }
}

private struct LegacyContactsTab: View {
    var body: some View {
        NavigationStack {
            Text("Contacts")
                .navigationTitle("Contacts")
        }
    }
}

private struct LegacyMomentsTab: View {
    var body: some View {
        NavigationStack {
            Text("Moments")
                .navigationTitle("Moments")
        }
    }
}

private struct MeTab: View {
    @ObservedObject var cloud: CloudAppState
    // `currentAccountId()` is an async actor method; it cannot be read
    // synchronously from `body`, so we load it into local state.
    @State private var accountId: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let accountId {
                        Text("Account ID: \(accountId.prefix(8))…")
                    }
                    Button("Sign out", role: .destructive) {
                        Task { await cloud.signOut() }
                    }
                }
                Section("Diagnostics") {
                    DiagnosticsLink(cloud: cloud)
                }
            }
            .navigationTitle("Me")
            .task { accountId = await cloud.auth.currentAccountId() }
        }
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
private struct DiagnosticsView: View {
    @ObservedObject var cloud: CloudAppState

    var body: some View {
        List {
            Section("Environment") {
                LabeledContent("Bundle", value: cloud.environment.bundleIdentifier)
                LabeledContent("Build", value: cloud.environment.buildNumber)
                LabeledContent("APNs", value: cloud.environment.apnsEnvironment.rawValue)
                LabeledContent("API", value: cloud.environment.apiBaseURL.absoluteString)
            }
            Section("Health") {
                Button("Run health check") {
                    Task { _ = try? await cloud.http.sendRaw(APIEndpoint(path: "/healthz")) }
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}

private struct DevSignInView: View {
    @ObservedObject var cloud: CloudAppState
    @State private var displayName: String = "Demo User"
    @State private var error: String?
    @State private var inFlight = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sign in") {
                    TextField("Display name", text: $displayName)
                    Button {
                        Task { await signIn() }
                    } label: {
                        if inFlight { ProgressView() } else { Text("Sign in (dev)") }
                    }
                    .disabled(inFlight)
                    Text("Production builds use Sign in with Apple + magic link; this panel is dev-only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Welcome")
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