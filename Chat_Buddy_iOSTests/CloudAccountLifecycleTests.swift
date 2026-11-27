import Foundation
import SwiftData
import XCTest
@testable import Chat_Buddy_iOS

@MainActor
final class CloudAccountLifecycleTests: XCTestCase {
    private let sharedConversation = "11111111-1111-4111-8111-111111111111"

    func testSwitchAndRestartKeepPrivateRowsOutboxAndOldCallbacksIsolated() async throws {
        let releaseA = DispatchSemaphore(value: 0)
        let delayedA = Data(#"{"cursor":"late-A","upserts":[],"tombstones":[],"serverTime":"2026-11-15T10:00:00Z","hasMore":false}"#.utf8)
        let script = OutboxHTTPStub.Script { call in
            switch (call.path, call.authorization) {
            case ("/v1/sync", "Bearer A"):
                return Self.sync()
            case ("/v1/sync", "Bearer B"):
                return .timeout
            case ("/v1/onboarding", _):
                return Self.json(#"{"state":"complete"}"#)
            case ("/v1/held", "Bearer A"):
                return .held(releaseA, 200, delayedA)
            default:
                throw URLError(.badServerResponse)
            }
        }
        let fixture = try Fixture(script)
        defer {
            releaseA.signal()
            fixture.close()
        }
        let first = try fixture.state()
        let state = first.cloud
        try await state.acceptSignIn(tokens("A"), generation: state.sessionGeneration)
        XCTAssertEqual(state.stage, .ready)
        try seed(state.container, account: "A")
        let key = try await state.conversations.enqueueMessage(conversationId: sharedConversation, content: "private pending A")
        state.pendingDeepLink = .chat(conversationId: sharedConversation)
        let oldRepository = state.conversations
        let oldTransport = state.http
        let oldModel = CloudChatViewModel(conversationId: sharedConversation, app: state)
        oldModel.draft = "late private draft"
        let held = Task {
            try await oldTransport.get(APIEndpoint(path: "/v1/held"), as: SyncCoordinator.ServerEnvelope.self)
        }
        try await waitForRequest(script, path: "/v1/held")

        await state.signOut()
        XCTAssertEqual(state.stage, .unauthenticated)
        XCTAssertNil(state.pendingDeepLink)
        let cleared = await first.auth.currentSession()
        XCTAssertNil(cleared)
        try await state.acceptSignIn(tokens("B"), generation: state.sessionGeneration)
        XCTAssertEqual(state.stage, .offline)
        await oldModel.send()
        releaseA.signal()
        do {
            _ = try await held.value
            XCTFail("A's delayed request returned after the account swap")
        } catch is CancellationError {}
        let obsoleteRows = await oldRepository.cachedMessages(conversationId: sharedConversation)
        XCTAssertTrue(obsoleteRows.isEmpty)
        let bInitialRows = await state.conversations.cachedConversationList()
        XCTAssertTrue(bInitialRows.isEmpty)
        XCTAssertTrue(state.outbox.loadPending(accountId: "A").isEmpty)
        XCTAssertTrue(state.outbox.loadPending(accountId: "B").isEmpty)
        try seed(state.container, account: "B")

        let reopened = try fixture.state()
        await reopened.cloud.bootstrap()
        XCTAssertEqual(reopened.cloud.stage, .offline)
        let bRows = await reopened.cloud.conversations.cachedMessages(conversationId: sharedConversation)
        XCTAssertEqual(bRows.map(\.content), ["private B"])
        XCTAssertNil(reopened.cloud.pendingDeepLink)
        XCTAssertTrue(reopened.cloud.outbox.loadPending(accountId: "A").isEmpty)
        let aStore = try fixture.accountStore("A")
        let aOutbox = OutboxStore(context: ModelContext(aStore))
        XCTAssertEqual(aOutbox.loadPending(accountId: "A").map(\.idempotencyKey), [key])
        XCTAssertFalse(script.requests.contains { $0.path?.hasSuffix("/messages") == true })
        await reopened.cloud.signOut()
    }

    func testDeletionFailureStaysRetryableAndAcknowledgedRequestErasesOnlyCurrentStore() async throws {
        let deleteAttempts = AttemptCounter()
        let script = OutboxHTTPStub.Script { call in
            switch call.path {
            case "/v1/sync": return Self.sync()
            case "/v1/onboarding": return Self.json(#"{"state":"complete"}"#)
            case "/v1/account/delete":
                if deleteAttempts.increment() == 1 {
                    return Self.json(#"{"error":{"code":"INTERNAL","message":"fixture unavailable"}}"#, status: 503)
                }
                return Self.json(#"{"ok":true,"deletionStartedAt":"2026-11-15T10:00:00Z"}"#)
            default: throw URLError(.badServerResponse)
            }
        }
        let fixture = try Fixture(script)
        defer { fixture.close() }
        let first = try fixture.state()
        let cloud = first.cloud
        try await cloud.acceptSignIn(tokens("A"), generation: cloud.sessionGeneration)
        try seed(cloud.container, account: "A")
        try seed(fixture.accountStore("B"), account: "B")
        let failed = await cloud.deleteAccount()
        XCTAssertFalse(failed)
        XCTAssertEqual(cloud.stage, .ready)
        XCTAssertEqual(cloud.accountDeletion, .requestFailed)
        let stillSignedIn = await first.auth.currentAccountId()
        XCTAssertEqual(stillSignedIn, "A")
        XCTAssertEqual(try ModelContext(cloud.container).fetchCount(FetchDescriptor<CachedMessage>()), 1)

        let acknowledged = await cloud.deleteAccount()
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(cloud.stage, .unauthenticated)
        XCTAssertEqual(cloud.accountDeletion, .pendingServerDeletion)
        let after = try fixture.state()
        await after.cloud.bootstrap()
        XCTAssertEqual(after.cloud.stage, .unauthenticated)
        let reopenedA = try fixture.accountStore("A")
        let reopenedB = try fixture.accountStore("B")
        XCTAssertEqual(try ModelContext(reopenedA).fetchCount(FetchDescriptor<CachedMessage>()), 0)
        XCTAssertEqual(try ModelContext(reopenedB).fetchCount(FetchDescriptor<CachedMessage>()), 1)
        let requests = script.requests.filter { $0.path == "/v1/account/delete" }
        XCTAssertEqual(requests.count, 2)
        for call in requests {
            XCTAssertEqual(call.method, "POST")
            XCTAssertEqual(call.authorization, "Bearer A")
            let body = try JSONSerialization.jsonObject(with: call.body) as? [String: String]
            XCTAssertEqual(body, ["confirmation": "delete my account"])
        }
    }

    func testLostDeletionReceiptRetriesOnceWithTheOriginalAuthorization() async throws {
        let attempts = AttemptCounter()
        let script = OutboxHTTPStub.Script { call in
            switch call.path {
            case "/v1/sync": return Self.sync()
            case "/v1/onboarding": return Self.json(#"{"state":"complete"}"#)
            case "/v1/account/delete":
                return attempts.increment() == 1 ? .timeout : Self.json(#"{"ok":true,"deletionStartedAt":"2026-11-15T10:00:00Z"}"#)
            default: throw URLError(.badServerResponse)
            }
        }
        let fixture = try Fixture(script)
        defer { fixture.close() }
        let first = try fixture.state()
        try await first.cloud.acceptSignIn(tokens("A"), generation: first.cloud.sessionGeneration)
        let accepted = await first.cloud.deleteAccount()
        XCTAssertTrue(accepted)
        XCTAssertEqual(first.cloud.accountDeletion, .pendingServerDeletion)
        let calls = script.requests.filter { $0.path == "/v1/account/delete" }
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls.allSatisfy { $0.authorization == "Bearer A" && $0.method == "POST" })
        XCTAssertEqual(calls.first?.body, calls.last?.body)
        XCTAssertFalse(script.requests.contains { $0.path == "/v1/auth/refresh" })
    }

    func testProtectedRequestsShareOneTokenRefreshAndRevocationClearsTheActiveScope() async throws {
        let release = DispatchSemaphore(value: 0)
        let renewal = Data(#"{"accessToken":"rotated","refreshToken":"rotated-refresh","accessExpiresAt":"2099-01-01T00:00:00Z"}"#.utf8)
        let unauthorized = #"{"error":{"code":"UNAUTHORIZED","message":"fixture rejected"}}"#
        let renewalAttempts = AttemptCounter()
        let script = OutboxHTTPStub.Script { call in
            switch call.path {
            case "/v1/sync": return Self.sync()
            case "/v1/onboarding": return Self.json(#"{"state":"complete"}"#)
            case "/v1/protected":
                return call.authorization == "Bearer rotated" ? Self.json(#"{"state":"complete"}"#) : Self.json(unauthorized, status: 401)
            case "/v1/revoked": return Self.json(unauthorized, status: 401)
            case "/v1/auth/refresh":
                return renewalAttempts.increment() == 1 ? .held(release, 200, renewal) : Self.json(unauthorized, status: 401)
            default: throw URLError(.badServerResponse)
            }
        }
        let fixture = try Fixture(script)
        defer {
            release.signal()
            fixture.close()
        }
        let first = try fixture.state()
        let cloud = first.cloud
        try await cloud.acceptSignIn(tokens("A"), generation: cloud.sessionGeneration)
        let http = cloud.http
        let protected = APIEndpoint(path: "/v1/protected")
        async let firstResponse = http.get(protected, as: OnboardingStatePayload.self)
        async let secondResponse = http.get(protected, as: OnboardingStatePayload.self)
        try await waitForRequest(script, path: "/v1/protected", count: 2)
        try await waitForRequest(script, path: "/v1/auth/refresh")
        release.signal()
        let responses = try await [firstResponse, secondResponse]
        XCTAssertEqual(responses.map(\.state), ["complete", "complete"])
        let refreshed = await first.auth.currentSession()
        XCTAssertEqual(refreshed?.refreshToken, "rotated-refresh")
        XCTAssertEqual(script.requests.filter { $0.path == "/v1/auth/refresh" }.count, 1)
        XCTAssertEqual(script.requests.filter { $0.path == "/v1/protected" }.count, 4)

        do {
            _ = try await http.get(APIEndpoint(path: "/v1/revoked"), as: OnboardingStatePayload.self)
            XCTFail("A rejected refresh cannot authorize a replay")
        } catch let error as APIError {
            XCTAssertEqual(error.code, .unauthorized)
        }
        XCTAssertEqual(cloud.stage, .unauthenticated)
        let revoked = await first.auth.currentSession()
        XCTAssertNil(revoked)
        let refreshCalls = script.requests.filter { $0.path == "/v1/auth/refresh" }
        XCTAssertEqual(refreshCalls.count, 2)
        XCTAssertTrue(refreshCalls.allSatisfy { $0.authorization == nil })
        let usedRefreshTokens = try refreshCalls.map { call in
            let body = try JSONSerialization.jsonObject(with: call.body) as? [String: String]
            return body?["refreshToken"]
        }
        XCTAssertEqual(usedRefreshTokens, ["refresh-A", "rotated-refresh"])
    }

    func testLegacyStoreMigrationMovesOnlyOwnerTaggedOutboxRows() throws {
        let schema = ModelContainerFactory.schema
        let legacy = try ModelContainerFactory.makeInMemory(schema: schema)
        let destination = try ModelContainerFactory.makeInMemory(schema: schema)
        try seed(legacy, account: "A")
        let oldOutbox = OutboxStore(context: ModelContext(legacy))
        let a = try oldOutbox.enqueue(accountId: "A", method: "POST", path: "/v1/fixture",
                                      idempotencyKey: "same-A", body: Data("old-A".utf8))
        _ = try oldOutbox.enqueue(accountId: "B", method: "POST", path: "/v1/fixture",
                                  idempotencyKey: "same-B", body: Data("old-B".utf8))
        try ModelContainerFactory.migrateLegacyOutbox(accountId: "A", from: legacy, to: destination)
        try ModelContainerFactory.migrateLegacyOutbox(accountId: "A", from: legacy, to: destination)
        let migrated = OutboxStore(context: ModelContext(destination))
        let remaining = OutboxStore(context: ModelContext(legacy))
        XCTAssertEqual(migrated.loadPending(accountId: "A"), [a])
        XCTAssertTrue(migrated.loadPending(accountId: "B").isEmpty)
        XCTAssertEqual(remaining.loadPending(accountId: "B").map(\.idempotencyKey), ["same-B"])
        XCTAssertTrue(remaining.loadPending(accountId: "A").isEmpty)
        XCTAssertEqual(try ModelContext(destination).fetchCount(FetchDescriptor<CachedMessage>()), 0)
        XCTAssertEqual(try ModelContext(legacy).fetchCount(FetchDescriptor<CachedMessage>()), 1)
    }

    private func tokens(_ account: String) -> AuthTokens {
        AuthTokens(accessToken: account, refreshToken: "refresh-\(account)", accountId: account,
                   actorId: "actor-\(account)", accessExpiresAt: Date().addingTimeInterval(3600))
    }

    private func seed(_ container: ModelContainer, account: String) throws {
        let context = ModelContext(container)
        context.insert(CachedConversation(id: sharedConversation, socialGraphId: "graph",
            type: "direct", publicName: "private \(account)", createdByActorId: "actor-\(account)",
            status: "active", createdAt: .now))
        context.insert(CachedMessage(id: "message-\(account)", conversationId: sharedConversation,
            senderActorId: "actor-\(account)", sequence: 1, clientIdempotencyKey: "remote-\(account)", kind: "text",
            content: "private \(account)", structuredPayload: nil, replyToMessageId: nil, burstId: nil,
            status: "sent", createdAt: .now, deletedAt: nil))
        try context.save()
    }

    private func waitForRequest(_ script: OutboxHTTPStub.Script, path: String, count: Int = 1) async throws {
        for _ in 0..<300 {
            if script.requests.filter({ $0.path == path }).count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.timedOut)
    }

    nonisolated private static func sync() -> OutboxHTTPStub.Reply {
        json(#"{"cursor":"fixture","upserts":[],"tombstones":[],"serverTime":"2026-11-15T10:00:00Z","hasMore":false}"#)
    }

    nonisolated private static func json(_ text: String, status: Int = 200) -> OutboxHTTPStub.Reply {
        .response(status, Data(text.utf8))
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let environment: AppEnvironment
        let session: URLSession
        let deviceContainer: ModelContainer

        init(_ script: OutboxHTTPStub.Script) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let url = OutboxHTTPStub.install(script)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [OutboxHTTPStub.self]
            session = URLSession(configuration: config)
            environment = AppEnvironment(apiBaseURL: url, realtimeURL: url, bundleIdentifier: root.lastPathComponent,
                                         buildNumber: "fixture", enableDiagnostics: false, apnsEnvironment: .sandbox)
            deviceContainer = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        }

        func state() throws -> (cloud: CloudAppState, auth: AuthSession) {
            let auth = AuthSession(environment: environment, service: "cloud-lifecycle-fixture")
            let cloud = try CloudAppState(environment: environment, auth: auth, deviceContainer: deviceContainer,
                                          urlSession: session, enablePush: false, enableRealtime: false) { accountId in
                try accountStore(accountId)
            }
            return (cloud, auth)
        }

        func accountStore(_ accountId: String) throws -> ModelContainer {
            try ModelContainerFactory.makeAccountStore(namespace: environment.bundleIdentifier, accountId: accountId, storageRoot: root)
        }

        func close() {
            session.invalidateAndCancel()
            OutboxHTTPStub.remove(environment.apiBaseURL)
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private nonisolated final class AttemptCounter: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var count = 0

    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
