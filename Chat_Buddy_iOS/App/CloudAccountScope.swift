import Foundation
import SwiftData
import os

public nonisolated final class CloudAccountLifetime: Sendable {
    private let active = OSAllocatedUnfairLock(initialState: true)

    var isActive: Bool { active.withLock { $0 } }

    func end() {
        active.withLock { $0 = false }
    }

    func check() throws {
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
    }
}

@MainActor
struct CloudAccountScope {
    let accountId: String?
    let lifetime = CloudAccountLifetime()
    let container: ModelContainer
    let http: HTTPClient
    let authService: AuthService
    let realtime: RealtimeClient
    let sync: SyncCoordinator
    let outbox: OutboxStore
    let cursorStore: SyncCursorStore
    let actors: ActorRepository
    let conversations: ConversationRepository
    let moments: MomentsRepository
    let contacts: ContactsRepository
    let weather: WeatherCapability
    let search: SearchCapability
    let calendarCoordinator: ClientActionCoordinator

    init(
        accountId: String?,
        container: ModelContainer,
        environment: AppEnvironment,
        auth: AuthSession,
        urlSession: URLSession?,
    ) {
        self.accountId = accountId
        self.container = container
        let context = ModelContext(container)
        let lifetime = self.lifetime
        let client = HTTPClient(
            environment: environment,
            session: auth,
            urlSession: urlSession ?? URLSession(configuration: .ephemeral),
            lifetime: lifetime,
            accountId: accountId,
            ownsURLSession: urlSession == nil,
        )
        http = client
        authService = AuthService(auth: auth, http: client, lifetime: lifetime)
        realtime = RealtimeClient(environment: environment, session: auth, onEvent: { _ in }, onGap: {})
        let cursor = SyncCursorStore(context: context)
        let mutations = OutboxStore(context: context)
        cursorStore = cursor
        outbox = mutations
        let conversationRepository = ConversationRepository(
            http: client,
            context: context,
            outbox: mutations,
            accountIdProvider: { lifetime.isActive ? accountId : nil },
            lifetime: lifetime,
        )
        conversations = conversationRepository
        sync = SyncCoordinator(
            http: client,
            context: context,
            cursorStore: cursor,
            outbox: mutations,
            flushOutbox: {
                do {
                    _ = try await conversationRepository.flushOutbox()
                } catch {
                    CloudLogger.sync.notice("outbox flush failed: \(String(describing: error), privacy: .private)")
                }
            },
            lifetime: lifetime,
        )
        actors = ActorRepository(http: client, context: context, lifetime: lifetime)
        moments = MomentsRepository(http: client, context: context, lifetime: lifetime)
        contacts = ContactsRepository(http: client, context: context, lifetime: lifetime)
        weather = WeatherCapability(http: client)
        search = SearchCapability(http: client)
        calendarCoordinator = ClientActionCoordinator(http: client, calendar: CalendarCapability())
    }

    func stop() async {
        lifetime.end()
        await http.invalidate()
        await realtime.pause()
    }
}
