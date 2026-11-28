import Combine
import Foundation
import SwiftData
import SwiftUI
import os

/// Cloud-first app state. This is the new entry point; the legacy
/// `AppState` (UserDefaults arrays + local AIPipeline) is being
/// deprecated per the skill's "Current-repository corrections".
///
/// Responsibilities:
///   - Owns the HTTPClient, AuthSession, RealtimeClient, repositories.
///   - Boots the model container and runs initial sync after auth.
///   - Routes on the four tabs: Chats (default), Contacts, Moments, Me.
///   - Drives onboarding into the Mira conversation; never renders
///     Mira as a special system bubble.
@MainActor
public final class CloudAppState: ObservableObject {
    public enum BootStage: String, Sendable, Equatable {
        case loading
        case unauthenticated
        case onboarding
        case ready
        case offline
    }

    public enum AccountDeletion: Sendable, Equatable {
        case idle
        case submitting
        case requestFailed
        case pendingServerDeletion
        case localCleanupFailed
    }

    @Published public private(set) var stage: BootStage = .loading
    @Published public private(set) var environment: AppEnvironment
    @Published public private(set) var errorMessage: String?
    /// Last realtime event, published so views can refresh the affected
    /// surface. Full per-event targeted refresh is TODO (see
    /// `handleRealtimeEvent`).
    @Published public private(set) var lastRealtimeEvent: RealtimeClient.RealtimeEvent?
    @Published public var selectedTab: CloudAppTab = CloudAppTab.defaultTab {
        didSet {
            deviceSettings.write(.lastSelectedTab, value: selectedTab.rawValue)
        }
    }
    @Published public var pendingDeepLink: DeepLinkRouter.PendingRoute?
    @Published public private(set) var accountDeletion: AccountDeletion = .idle
    @Published public private(set) var sessionGeneration = UUID()
    @Published private(set) var archiveMergeRevision = UUID()

    public var container: ModelContainer { scope.container }
    public let auth: AuthSession
    public var http: HTTPClient { scope.http }
    public var realtime: RealtimeClient { scope.realtime }
    public var sync: SyncCoordinator { scope.sync }
    public var actors: ActorRepository { scope.actors }
    public var conversations: ConversationRepository { scope.conversations }
    public var moments: MomentsRepository { scope.moments }
    public var contacts: ContactsRepository { scope.contacts }
    public let calendar: CalendarCapability
    public var weather: WeatherCapability { scope.weather }
    public var search: SearchCapability { scope.search }
    public var calendarCoordinator: ClientActionCoordinator { scope.calendarCoordinator }
    public let push: PushNotificationService
    public let router = DeepLinkRouter()
    public var outbox: OutboxStore { scope.outbox }
    public var cursorStore: SyncCursorStore { scope.cursorStore }
    public let legacyImporter: LegacyImporter
    public let deviceSettings: DeviceSettingsStore

    private let logger = CloudLogger.auth
    private let unauthenticatedContainer: ModelContainer
    private let makeAccountContainer: (String) throws -> ModelContainer
    private let urlSession: URLSession?
    private let enablePush: Bool
    private let enableRealtime: Bool
    private var scope: CloudAccountScope
    private var changingSession = false
    private var revocationPending = false
    private var pushBootstrapped = false

    /// Non-isolated teardown on purpose — see `LegacyImporter.nonisolated deinit`
    /// for the full story (isolated deinit + release from an async frame =
    /// double free). The deinit only releases the sub-objects, none of which
    /// needs the main actor to be torn down.
    nonisolated deinit {}

    public convenience init(
        environment: AppEnvironment = .resolve(),
        container: ModelContainer? = nil,
    ) throws {
        let deviceContainer = try container ?? ModelContainerFactory.makeDeviceSettings()
        try self.init(
            environment: environment,
            auth: AuthSession(environment: environment),
            deviceContainer: deviceContainer,
            makeAccountContainer: { accountId in
                try ModelContainerFactory.makeAccountStore(
                    namespace: "\(environment.bundleIdentifier)\u{0}\(environment.apiBaseURL.absoluteString)",
                    accountId: accountId,
                )
            },
        )
    }

    init(
        environment: AppEnvironment,
        auth: AuthSession,
        deviceContainer: ModelContainer,
        urlSession: URLSession? = nil,
        enablePush: Bool = true,
        enableRealtime: Bool = true,
        makeAccountContainer: @escaping (String) throws -> ModelContainer,
    ) throws {
        self.environment = environment
        self.auth = auth
        self.urlSession = urlSession
        self.enablePush = enablePush
        self.enableRealtime = enableRealtime
        self.makeAccountContainer = makeAccountContainer
        let signedOut = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        self.unauthenticatedContainer = signedOut
        self.scope = CloudAccountScope(
            accountId: nil,
            container: signedOut,
            environment: environment,
            auth: auth,
            urlSession: urlSession,
        )
        self.deviceSettings = DeviceSettingsStore(context: ModelContext(deviceContainer))
        self.calendar = CalendarCapability()
        self.push = PushNotificationService.shared
        self.legacyImporter = LegacyImporter()
        if let rawTab = deviceSettings.read(.lastSelectedTab),
           let restoredTab = CloudAppTab(rawValue: rawTab) {
            selectedTab = restoredTab
        }
    }

    /// Boot the cloud client. Called from `init` of the SwiftUI App.
    public func bootstrap() async {
        guard let session = await auth.currentSession() else {
            stage = .unauthenticated
            return
        }
        do {
            try await establishSession(accountId: session.accountId, tokens: nil, appleSubject: nil)
        } catch {
            errorMessage = "cloud_account_cache_open_failed"
            await endSession(eraseCache: false)
        }
    }

    /// Decide the post-sync stage. Per skill §"Mira onboarding" the
    /// conversation resumes whenever the server says onboarding is not
    /// complete — this is the forkable breakpoint resume; leaving
    /// mid-onboarding never loses progress.
    func routeAfterSync() async {
        let current = scope
        guard current.accountId != nil, current.lifetime.isActive else { return }
        do {
            let resume = try await current.http.get(Endpoints.onboardingState, as: OnboardingStatePayload.self)
            try current.lifetime.check()
            let serverState = OnboardingGate.ServerState.parse(
                resume.state, step: resume.step, awaitingUser: resume.awaitingUser,
            )
            stage = OnboardingGate.shouldResumeOnboarding(serverState) ? .onboarding : .ready
            errorMessage = nil
            if stage == .ready { await bootstrapPushIfReady() }
        } catch {
            guard current.lifetime.isActive else { return }
            stage = .offline
            errorMessage = "cloud_onboarding_unavailable"
        }
    }

    /// Register APNs once the user reaches the main app. Permission is
    /// requested contextually (after onboarding), not at first launch.
    private func bootstrapPushIfReady() async {
        let lifetime = scope.lifetime
        guard enablePush, lifetime.isActive, scope.accountId != nil, !pushBootstrapped else { return }
        pushBootstrapped = true
        await push.bootstrap(shouldRegister: { lifetime.isActive }) { [weak self] route in
            // The route handler is synchronous and may run off the main actor;
            // hop back explicitly before touching view state.
            Task { @MainActor [weak self] in
                guard lifetime.isActive else { return }
                await self?.handlePushRoute(route)
            }
        }
    }

    /// Route a push into the right tab/conversation. Payload carries only
    /// opaque route data (skill §11).
    private func handlePushRoute(_ route: PushRoute) async {
        switch route {
        case .chat, .proactiveMessage:
            selectedTab = .chats
        case .friendRequest:
            selectedTab = .contacts
        case .groupInvitation:
            selectedTab = .contacts
        case .moment:
            selectedTab = .moments
        }
    }

    /// Best-effort cached display title for a conversation, read on the
    /// main-actor model context. Falls back to nil (caller localizes).
    func cachedConversationTitle(conversationId: String) -> String? {
        guard scope.accountId != nil, scope.lifetime.isActive else { return nil }
        let context = ModelContext(container)
        if let conversation = (try? context.fetch(
            FetchDescriptor<CachedConversation>(predicate: #Predicate { $0.id == conversationId }),
        ))?.first, let name = conversation.publicName, !name.isEmpty {
            return name
        }
        if let actor = (try? context.fetch(
            FetchDescriptor<CachedActor>(predicate: #Predicate { $0.id == conversationId }),
        ))?.first {
            return actor.publicName
        }
        return nil
    }

    /// Install the real realtime callbacks. Deferred until `bootstrap`
    /// (awaited before `realtime.connect()`) because closures cannot
    /// capture `self` mid-init.
    private func installRealtimeHandlers(for scope: CloudAccountScope) async {
        let lifetime = scope.lifetime
        await scope.realtime.setHandlers(
            onEvent: { [weak self] event in
                await self?.handleRealtimeEvent(event, lifetime: lifetime)
            },
            onGap: { [weak self] in
                await self?.handleRealtimeGap(lifetime: lifetime)
            },
        )
    }

    /// A realtime event arrived. Minimum viable handling: publish the
    /// event and run a cursor-based delta sync so the cache catches up.
    /// TODO(skill §"Realtime client"): parse the event channel/payload and
    /// refresh only the affected conversation/moment instead of a full
    /// delta pass.
    func handleRealtimeEvent(_ event: RealtimeClient.RealtimeEvent, lifetime: CloudAccountLifetime) async {
        guard scope.lifetime === lifetime, lifetime.isActive else { return }
        lastRealtimeEvent = event
        await runDeltaSyncAfterRealtime()
    }

    /// The server reported an event gap: resume must be a delta sync.
    func handleRealtimeGap(lifetime: CloudAccountLifetime) async {
        guard scope.lifetime === lifetime, lifetime.isActive else { return }
        logger.notice("realtime gap detected; running delta sync")
        await runDeltaSyncAfterRealtime()
    }

    private func runDeltaSyncAfterRealtime() async {
        let current = scope
        guard let accountId = current.accountId, current.lifetime.isActive else { return }
        do {
            try await current.sync.runSync(accountId: accountId)
        } catch {
            logger.notice(
                "realtime delta sync failed: \(String(describing: error), privacy: .public)",
            )
        }
    }

    /// Explicit boot-stage transition. `stage` has a private setter so
    /// views can't clobber the boot pipeline; onboarding/auth flows move
    /// through this gate instead.
    func transition(to newStage: BootStage) {
        stage = newStage
        if newStage == .ready {
            // Contextual push permission: only after reaching (or
            // skipping past) onboarding — never at first launch.
            Task { await bootstrapPushIfReady() }
        }
    }

    /// Sign-in via the dev convenience endpoint. Production swaps in
    /// Sign in with Apple + magic link.
    public func devSignIn(displayName: String) async throws {
        struct Body: Codable { let displayName: String }
        struct Response: Codable, Sendable {
            let accessToken: String
            let accessExpiresAt: Date
            let refreshToken: String
            let refreshExpiresAt: Date
            let accountId: String
            let actorId: String
        }
        let initialGeneration = sessionGeneration
        let body = Body(displayName: displayName)
        let response = try await http.send(
            Endpoints.devSignIn(displayName: displayName),
            method: "POST",
            body: body,
            as: Response.self,
        )
        try await acceptSignIn(
            AuthTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                accountId: response.accountId,
                actorId: response.actorId,
                accessExpiresAt: response.accessExpiresAt,
            ),
            generation: initialGeneration,
        )
    }

    func acceptSignIn(_ tokens: AuthTokens, generation: UUID, appleSubject: String? = nil) async throws {
        guard generation == sessionGeneration else { throw CancellationError() }
        try await establishSession(accountId: tokens.accountId, tokens: tokens, appleSubject: appleSubject)
    }

    private func establishSession(accountId: String, tokens: AuthTokens?, appleSubject: String?) async throws {
        guard !changingSession, accountDeletion != .submitting, !accountId.isEmpty else {
            throw CancellationError()
        }
        let nextContainer = try makeAccountContainer(accountId)
        changingSession = true
        let next = CloudAccountScope(
            accountId: accountId,
            container: nextContainer,
            environment: environment,
            auth: auth,
            urlSession: urlSession,
        )
        let previous = scope
        previous.lifetime.end()
        stage = .loading
        clearAccountPresentation()
        errorMessage = nil
        accountDeletion = .idle
        if enablePush, previous.accountId != nil { await push.unregister() }
        await previous.stop()
        if let tokens {
            await auth.update(tokens: tokens)
            if let appleSubject {
                await auth.storeAppleSubject(appleSubject)
            } else {
                await auth.clearAppleSubject()
            }
        }
        scope = next
        await installRealtimeHandlers(for: next)
        let lifetime = next.lifetime
        await next.authService.setRevocationHandler { [weak self] _ in
            await self?.onSessionRevoked(lifetime: lifetime)
        }
        await next.authService.installUnauthorizedHandler(on: next.http)
        changingSession = false
        await runInitialSync()
    }

    private func clearAccountPresentation() {
        sessionGeneration = UUID()
        lastRealtimeEvent = nil
        pendingDeepLink = nil
        router.pending = nil
        revocationPending = false
        pushBootstrapped = false
        selectedTab = .chats
    }

    /// The server first schedules deletion. Local cleanup follows only
    /// after receiving a valid acknowledgement.
    @discardableResult
    public func deleteAccount() async -> Bool {
        guard scope.accountId != nil, accountDeletion != .submitting, !changingSession else {
            return false
        }
        accountDeletion = .submitting
        let current = scope
        struct Request: Codable { let confirmation: String }
        struct Receipt: Decodable, Sendable { let ok: Bool; let deletionStartedAt: Date }
        do {
            let receipt = try await current.http.send(
                Endpoints.accountDelete, method: "POST",
                body: Request(confirmation: "delete my account"), as: Receipt.self,
            )
            guard receipt.ok else {
                await markDeletionUnconfirmed()
                return false
            }
        } catch {
            await markDeletionUnconfirmed()
            return false
        }
        accountDeletion = await endSession(eraseCache: true) ? .pendingServerDeletion : .localCleanupFailed
        return true
    }

    private func markDeletionUnconfirmed() async {
        accountDeletion = .requestFailed
        logger.notice("account deletion was not acknowledged")
        if revocationPending { await endSession(eraseCache: false) }
    }

    public func signOut() async {
        guard !changingSession, accountDeletion != .submitting else { return }
        await endSession(eraseCache: false)
    }

    private func onSessionRevoked(lifetime: CloudAccountLifetime) async {
        guard scope.lifetime === lifetime, lifetime.isActive, !changingSession else { return }
        if accountDeletion == .submitting {
            revocationPending = true
            return
        }
        await endSession(eraseCache: false)
    }

    func resume() async {
        let active = scope
        guard active.accountId != nil, active.lifetime.isActive else { return }
        if await active.authService.checkAppleCredentialRevoked() {
            await active.authService.performSessionRevocation(.appleCredentialRevoked)
        } else if active.lifetime.isActive {
            await runInitialSync()
        }
    }

    @discardableResult
    private func endSession(eraseCache: Bool) async -> Bool {
        changingSession = true
        defer { changingSession = false }
        let previous = scope
        previous.lifetime.end()
        stage = .loading
        clearAccountPresentation()
        await previous.stop()
        if enablePush { await push.unregister() }
        var cleared = await auth.clear()
        scope = CloudAccountScope(
            accountId: nil,
            container: unauthenticatedContainer,
            environment: environment,
            auth: auth,
            urlSession: urlSession,
        )
        if eraseCache {
            do {
                try previous.container.erase()
            } catch {
                cleared = false
                logger.error("account cache erase failed")
            }
        }
        stage = .unauthenticated
        if !cleared { errorMessage = "cloud_account_cleanup_failed" }
        return cleared
    }

    /// Archive writes deliberately don't emit message-send events. Read only
    /// authoritative affected timelines, bound to the old account's lifetime.
    func refreshAfterPortableMerge(_ receipt: PortableBackupMergeService.Receipt, generation: UUID) async throws {
        let current = scope
        guard generation == sessionGeneration, current.accountId != nil,
              accountDeletion != .submitting else { throw CancellationError() }
        try current.lifetime.check()
        guard let actorId = await auth.currentActorId() else { throw CancellationError() }
        try current.lifetime.check()
        try await current.conversations.refreshArchiveMerge(
            conversationIds: receipt.affectedConversationIds,
            starts: receipt.affectedConversationStarts,
            myActorId: actorId,
            restoredConversationIds: receipt.restoredConversationIds ?? [],
        )
        try current.lifetime.check()
        archiveMergeRevision = UUID()
    }

    public func runInitialSync() async {
        let current = scope
        guard let accountId = current.accountId, current.lifetime.isActive,
              accountDeletion != .submitting
        else { return }
        do {
            try await current.sync.initialSync(accountId: accountId)
            try current.lifetime.check()
            if enableRealtime { await current.realtime.connect() }
            try current.lifetime.check()
            if stage == .loading || stage == .offline {
                await routeAfterSync()
            }
        } catch {
            guard current.lifetime.isActive, !Task.isCancelled else { return }
            logger.notice("initial sync failed: \(String(describing: error), privacy: .private)")
            errorMessage = "cloud_sync_unavailable"
            stage = .offline
        }
    }
}

/// `/v1/onboarding` response payload (server-authoritative state machine).
public struct OnboardingStatePayload: Codable, Sendable {
    public let state: String
    public let step: Int?
    public let awaitingUser: Bool?
    public let conversationId: String?
    public let facts: [String: String]?

    enum CodingKeys: String, CodingKey {
        case state, step, facts, conversationId
        case awaitingUser = "awaiting_user"
    }

    public init(
        state: String,
        step: Int? = nil,
        awaitingUser: Bool? = nil,
        conversationId: String? = nil,
        facts: [String: String]? = nil,
    ) {
        self.state = state
        self.step = step
        self.awaitingUser = awaitingUser
        self.conversationId = conversationId
        self.facts = facts
    }
}
