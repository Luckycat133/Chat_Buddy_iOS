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

    @Published public private(set) var stage: BootStage = .loading
    @Published public private(set) var environment: AppEnvironment
    @Published public private(set) var errorMessage: String?
    /// Last realtime event, published so views can refresh the affected
    /// surface. Full per-event targeted refresh is TODO (see
    /// `handleRealtimeEvent`).
    @Published public private(set) var lastRealtimeEvent: RealtimeClient.RealtimeEvent?
    @Published public var selectedTab: CloudAppTab = CloudAppTab.defaultTab
    @Published public var pendingDeepLink: DeepLinkRouter.PendingRoute?

    public let container: ModelContainer
    public let auth: AuthSession
    public let http: HTTPClient
    public let realtime: RealtimeClient
    public let sync: SyncCoordinator
    public let actors: ActorRepository
    public let conversations: ConversationRepository
    public let moments: MomentsRepository
    public let calendar: CalendarCapability
    public let weather: WeatherCapability
    public let search: SearchCapability
    public let calendarCoordinator: ClientActionCoordinator
    public let push: PushNotificationService
    public let router = DeepLinkRouter()
    public let outbox: OutboxStore
    public let cursorStore: SyncCursorStore
    public let legacyImporter: LegacyImporter

    private let logger = CloudLogger.auth

    public init(
        environment: AppEnvironment = .resolve(),
        container: ModelContainer? = nil,
    ) throws {
        self.environment = environment
        let resolvedContainer = try container ?? ModelContainerFactory.make(schema: ModelContainerFactory.schema)
        self.container = resolvedContainer
        let context = ModelContext(resolvedContainer)
        let session = AuthSession(environment: environment)
        let client = HTTPClient(environment: environment, session: session)
        let realtimeClient = RealtimeClient(
            environment: environment,
            session: session,
            onEvent: { _ in }, // real handlers installed in bootstrap()
            onGap: { },
        )
        self.auth = session
        self.http = client
        self.realtime = realtimeClient
        self.cursorStore = SyncCursorStore(context: context)
        self.outbox = OutboxStore(context: context)
        // The repository must exist before the sync coordinator so the
        // coordinator's flush closure can replay the real outbox.
        let conversationsRepository = ConversationRepository(
            http: client,
            context: context,
            outbox: outbox,
            accountIdProvider: { [weak session] in await session?.currentAccountId() },
        )
        let coordinator = SyncCoordinator(
            http: client,
            context: context,
            cursorStore: cursorStore,
            outbox: outbox,
            flushOutbox: {
                do {
                    _ = try await conversationsRepository.flushOutbox()
                } catch {
                    CloudLogger.sync.notice(
                        "outbox flush failed: \(String(describing: error), privacy: .public)",
                    )
                }
            },
        )
        self.sync = coordinator
        self.actors = ActorRepository(http: client, context: context)
        self.conversations = conversationsRepository
        self.moments = MomentsRepository(http: client, context: context)
        self.calendar = CalendarCapability()
        self.weather = WeatherCapability(http: client)
        self.search = SearchCapability(http: client)
        self.calendarCoordinator = ClientActionCoordinator(http: client, calendar: CalendarCapability())
        self.push = PushNotificationService.shared
        self.legacyImporter = LegacyImporter()
    }

    /// Boot the cloud client. Called from `init` of the SwiftUI App.
    public func bootstrap() async {
        await installRealtimeHandlers()
        await auth.reload()
        if await auth.isAuthenticated() {
            await runInitialSync()
            // runInitialSync sets `.offline` on failure; don't clobber it
            // with `.ready` when the sync actually failed.
            if stage != .offline {
                stage = .ready
            }
        } else {
            stage = .unauthenticated
        }
    }

    /// Install the real realtime callbacks. Deferred until `bootstrap`
    /// (awaited before `realtime.connect()`) because closures cannot
    /// capture `self` mid-init.
    private func installRealtimeHandlers() async {
        await realtime.setHandlers(
            onEvent: { [weak self] event in
                await self?.handleRealtimeEvent(event)
            },
            onGap: { [weak self] in
                await self?.handleRealtimeGap()
            },
        )
    }

    /// A realtime event arrived. Minimum viable handling: publish the
    /// event and run a cursor-based delta sync so the cache catches up.
    /// TODO(skill §"Realtime client"): parse the event channel/payload and
    /// refresh only the affected conversation/moment instead of a full
    /// delta pass.
    func handleRealtimeEvent(_ event: RealtimeClient.RealtimeEvent) async {
        lastRealtimeEvent = event
        await runDeltaSyncAfterRealtime()
    }

    /// The server reported an event gap: resume must be a delta sync.
    func handleRealtimeGap() async {
        logger.notice("realtime gap detected; running delta sync")
        await runDeltaSyncAfterRealtime()
    }

    private func runDeltaSyncAfterRealtime() async {
        guard let accountId = await auth.currentAccountId() else { return }
        do {
            try await sync.runSync(accountId: accountId)
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
        let body = Body(displayName: displayName)
        let response = try await http.send(
            Endpoints.devSignIn(displayName: displayName),
            method: "POST",
            body: body,
            as: Response.self,
        )
        await auth.update(
            tokens: AuthTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                accountId: response.accountId,
                actorId: response.actorId,
                accessExpiresAt: response.accessExpiresAt,
            ),
        )
        await runInitialSync()
        // Same rule as bootstrap(): a failed initial sync already moved us
        // to `.offline`; don't overwrite it with `.onboarding`.
        if stage != .offline {
            stage = .onboarding
        }
    }

    public func signOut() async {
        await auth.clear()
        // Legacy UserDefaults data is NOT erased here: it is the import
        // source for `LegacyImporter`, which must run (and succeed) before
        // anything is deleted. See LegacyImporter.eraseLegacyKeys().
        stage = .unauthenticated
    }

    public func runInitialSync() async {
        guard let accountId = await auth.currentAccountId() else { return }
        do {
            try await sync.initialSync(accountId: accountId)
            await realtime.connect()
        } catch {
            logger.notice("initial sync failed: \(String(describing: error), privacy: .public)")
            errorMessage = String(describing: error)
            stage = .offline
        }
    }
}

private extension AuthSession {
    /// Refresh the in-memory token cache from Keychain at boot.
    func reload() async {
        _ = await currentAccessToken()
    }
}