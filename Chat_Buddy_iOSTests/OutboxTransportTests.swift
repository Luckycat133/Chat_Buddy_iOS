import Foundation
import SwiftData
import XCTest
@testable import Chat_Buddy_iOS

@MainActor
final class OutboxTransportTests: XCTestCase {
    private let accountId = "outbox-fixture-account"
    private let conversationId = "11111111-1111-4111-8111-111111111111"
    private let replyId = "22222222-2222-4222-8222-222222222222"
    private let messageId = "33333333-3333-4333-8333-333333333333"
    private let content = "你好 👋\nsecond line"

    func testTimedOutSendReplaysSameJSONAndIdempotencyKeyAfterStoreReopen() async throws {
        let reply = Data("{\"id\":\"\(messageId)\",\"sequence\":7}".utf8)
        // The first request's response is lost. The simulated server returns
        // the original committed row when the same key is used on retry.
        let script = OutboxHTTPStub.Script([.timeout, .response(201, reply)])
        let url = OutboxHTTPStub.install(script)
        defer { OutboxHTTPStub.remove(url) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let http = makeClient(url, session: session)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("outbox.store")

        let key: String
        let persistedBody: Data
        do {
            let context = try fileContext(at: storeURL)
            let outbox = OutboxStore(context: context)
            let repository = makeRepository(http, context: context, outbox: outbox)
            key = try await repository.enqueueMessage(
                conversationId: conversationId, content: content, replyToMessageId: replyId,
            )
            let queued = try XCTUnwrap(outbox.loadPending(accountId: accountId).first)
            XCTAssertEqual(queued.state, .queued)
            persistedBody = queued.bodyData
            do {
                _ = try await repository.flushOne(idempotencyKey: key)
                XCTFail("The first request should time out")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .timedOut)
            }
            let pending = outbox.loadPending(accountId: accountId)
            XCTAssertEqual(pending.map(\.idempotencyKey), [key])
            XCTAssertEqual(pending.first?.attempts, 1)
            XCTAssertEqual(pending.first?.state, .failed)
            let rows = ChatOutboxReducer.merge(server: [], outbox: outbox.pendingSnapshots(accountId: accountId))
            XCTAssertEqual(rows.map(\.status), [.failed])
        }

        let context = try fileContext(at: storeURL)
        let outbox = OutboxStore(context: context)
        let repository = makeRepository(http, context: context, outbox: outbox)
        let reopened = try XCTUnwrap(outbox.loadPending(accountId: accountId).first)
        XCTAssertEqual(reopened.idempotencyKey, key)
        XCTAssertEqual(reopened.bodyData, persistedBody)
        XCTAssertEqual(reopened.state, .failed)
        XCTAssertEqual(reopened.attempts, 1)

        let results = try await repository.flushOutbox()
        XCTAssertEqual(results.map(\.accepted), [true])
        XCTAssertEqual(results.map(\.messageId), [messageId])
        XCTAssertEqual(results.map(\.sequence), [7])
        XCTAssertTrue(outbox.loadUnsettled(accountId: accountId).isEmpty)
        let requests = script.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            try assertMessageRequest(request, key: key, replyId: replyId)
            XCTAssertEqual(request.body, persistedBody)
        }
    }

    func testConflictRemainsVisibleUntilAuthoritativeEchoResolvesOneRow() async throws {
        let conflict = Data(#"{"error":{"code":"CONFLICT","message":"Accepted key needs reconciliation"}}"#.utf8)
        let script = OutboxHTTPStub.Script([.response(409, conflict)])
        let url = OutboxHTTPStub.install(script)
        defer { OutboxHTTPStub.remove(url) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let http = makeClient(url, session: session)
        let context = ModelContext(try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema))
        let outbox = OutboxStore(context: context)
        let repository = makeRepository(http, context: context, outbox: outbox)
        let key = try await repository.enqueueMessage(conversationId: conversationId, content: content)

        let result = try await repository.flushOne(idempotencyKey: key)
        XCTAssertTrue(result.conflict)
        XCTAssertFalse(result.accepted)
        let snapshots = outbox.pendingSnapshots(accountId: accountId)
        let rows = ChatOutboxReducer.merge(server: [], outbox: snapshots)
        XCTAssertEqual(rows.map(\.status), [.conflict])
        XCTAssertEqual(rows.map(\.idempotencyKey), [key])
        let noReplay = try await repository.flushOutbox()
        XCTAssertTrue(noReplay.isEmpty)
        XCTAssertEqual(script.requests.count, 1)
        try assertMessageRequest(XCTUnwrap(script.requests.first), key: key, replyId: nil)

        let echo = try syncResponse(for: key)
        script.append(.response(200, echo))
        script.append(.response(200, echo))
        let coordinator = SyncCoordinator(
            http: http, context: context, cursorStore: SyncCursorStore(context: context),
            outbox: outbox, flushOutbox: {},
        )
        try await coordinator.runSync(accountId: accountId)
        try await coordinator.runSync(accountId: accountId)

        XCTAssertTrue(outbox.loadUnsettled(accountId: accountId).isEmpty)
        let messages = await repository.cachedMessages(conversationId: conversationId)
        XCTAssertEqual(messages.map(\.id), [messageId])
        XCTAssertEqual(messages.map(\.sequence), [7])
        let delivered = ChatOutboxReducer.merge(server: messages, outbox: snapshots)
        XCTAssertEqual(delivered.map(\.id), [messageId])
        XCTAssertEqual(delivered.map(\.status), [.delivered])
        XCTAssertEqual(script.requests.map(\.method), ["POST", "GET", "GET"])
    }

    func testSparseReadCursorStaysActorScopedAfterRetryingCachedRead() async throws {
        let body = Data("""
        {"items":[{"id":"\(conversationId)","type":"group","publicName":"Fixture",
        "createdAt":"2026-11-27T00:00:00Z","lastReadSequence":9}]}
        """.utf8)
        let script = OutboxHTTPStub.Script([.timeout, .response(200, body)])
        let url = OutboxHTTPStub.install(script)
        defer { OutboxHTTPStub.remove(url) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let context = ModelContext(try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema))
        let outbox = OutboxStore(context: context)
        let repository = makeRepository(makeClient(url, session: session), context: context, outbox: outbox)

        do {
            _ = try await repository.listConversations()
            XCTFail("The first list request should time out")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }
        let summaries = try await repository.listConversations()
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.lastReadSequence, 9)
        let messages = [10, 12].map { sequence in
            RemoteMessageDTO(
                id: "message-\(sequence)", conversationId: conversationId, senderActorId: "friend",
                sequence: sequence, clientIdempotencyKey: "fixture-\(sequence)", kind: "text",
                content: "message", structuredPayload: nil, replyToMessageId: nil, burstId: nil,
                status: "accepted", createdAt: Date(), editedAt: nil, deletedAt: nil,
            )
        }
        await repository.hydrateOnboardingConversation(summary: summary, messages: messages, myActorId: "owner")
        context.insert(CachedConversationMember(
            conversationId: conversationId, actorId: "friend", status: "active", role: "member",
            invitedByActorId: nil, joinedAt: nil, leftAt: nil, lastReadSequence: 3,
        ))
        try context.save()
        let before = await repository.cachedConversationList(myActorId: "owner")
        XCTAssertEqual(before.first?.unreadCount, 2)
        await repository.markReadLocally(conversationId: conversationId, myActorId: "owner")
        let after = await repository.cachedConversationList(myActorId: "owner")
        XCTAssertEqual(after.first?.unreadCount, 0)
        let persisted = try context.fetch(FetchDescriptor<CachedConversationMember>())
        XCTAssertEqual(persisted.first(where: { $0.actorId == "owner" })?.lastReadSequence, 12)
        XCTAssertEqual(persisted.first(where: { $0.actorId == "friend" })?.lastReadSequence, 3)
    }

    private func assertMessageRequest(
        _ request: OutboxHTTPStub.CapturedRequest, key: String, replyId: String?,
    ) throws {
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/conversations/\(conversationId)/messages")
        XCTAssertEqual(request.contentType, "application/json")
        XCTAssertEqual(request.idempotencyKey, key)
        let json = try JSONSerialization.jsonObject(with: request.body, options: [.fragmentsAllowed])
        let body = try XCTUnwrap(json as? [String: String], "Message must be a JSON object")
        XCTAssertEqual(body["clientIdempotencyKey"], key)
        XCTAssertEqual(body["content"], content)
        XCTAssertEqual(body["replyToMessageId"], replyId)
    }

    private func fileContext(at url: URL) throws -> ModelContext {
        let schema = ModelContainerFactory.schema
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OutboxHTTPStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeClient(_ url: URL, session: URLSession) -> HTTPClient {
        let environment = AppEnvironment(
            apiBaseURL: url, realtimeURL: url, bundleIdentifier: "outbox-test", buildNumber: "1",
            enableDiagnostics: false, apnsEnvironment: .sandbox,
        )
        return HTTPClient(
            environment: environment,
            session: AuthSession(environment: environment, service: "outbox-test.\(UUID().uuidString)"),
            urlSession: session,
        )
    }

    private func makeRepository(
        _ http: HTTPClient, context: ModelContext, outbox: OutboxStore,
    ) -> ConversationRepository {
        ConversationRepository(http: http, context: context, outbox: outbox) { [accountId] in accountId }
    }

    private func syncResponse(for key: String) throws -> Data {
        let message = RemoteMessageDTO(
            id: messageId, conversationId: conversationId,
            senderActorId: "44444444-4444-4444-8444-444444444444", sequence: 7,
            clientIdempotencyKey: key, kind: "text", content: content, structuredPayload: nil,
            replyToMessageId: nil, burstId: nil, status: "accepted", createdAt: Date(timeIntervalSince1970: 100),
            editedAt: nil, deletedAt: nil,
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractional
        let payload = ServerPayload(data: try encoder.encode(message))
        let envelope = SyncCoordinator.ServerEnvelope(
            cursor: "message-7", upserts: [SyncUpsert(table: "messages", id: messageId, payload: payload)],
            tombstones: [], serverTime: Date(timeIntervalSince1970: 101), hasMore: false,
        )
        return try encoder.encode(envelope)
    }
}

final class OutboxHTTPStub: URLProtocol, @unchecked Sendable {
    struct CapturedRequest: Sendable {
        let method: String?
        let path: String?
        let contentType: String?
        let idempotencyKey: String?
        let authorization: String?
        let body: Data
    }

    enum Reply: Sendable {
        case timeout
        case response(Int, Data)
        case held(DispatchSemaphore, Int, Data)
    }

    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [Reply]
        private var captured: [CapturedRequest] = []
        private let handler: (@Sendable (CapturedRequest) throws -> Reply)?

        init(_ replies: [Reply]) {
            self.replies = replies
            self.handler = nil
        }

        init(handler: @escaping @Sendable (CapturedRequest) throws -> Reply) {
            self.replies = []
            self.handler = handler
        }

        var requests: [CapturedRequest] {
            lock.withLock { captured }
        }

        func append(_ reply: Reply) {
            lock.withLock { replies.append(reply) }
        }

        func next(for request: CapturedRequest) throws -> Reply {
            if let handler {
                lock.withLock { captured.append(request) }
                return try handler(request)
            }
            return try lock.withLock {
                captured.append(request)
                guard !replies.isEmpty else { throw URLError(.badServerResponse) }
                return replies.removeFirst()
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var scripts: [String: Script] = [:]
    private let stateLock = NSLock()
    nonisolated(unsafe) private var stopped = false

    static func install(_ script: Script) -> URL {
        let host = "\(UUID().uuidString.lowercased()).outbox.invalid"
        lock.withLock { scripts[host] = script }
        return URL(string: "https://\(host)")!
    }

    static func remove(_ url: URL) {
        _ = lock.withLock { scripts.removeValue(forKey: url.host ?? "") }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".outbox.invalid") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let url = request.url, let host = url.host,
                  let script = Self.lock.withLock({ Self.scripts[host] }) else {
                throw URLError(.unsupportedURL)
            }
            let captured = CapturedRequest(
                method: request.httpMethod, path: url.path,
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                body: try Self.bodyBytes(request),
            )
            switch try script.next(for: captured) {
            case .timeout:
                throw URLError(.timedOut)
            case .response(let status, let body):
                finish(url: url, status: status, body: body)
            case .held(let gate, let status, let body):
                DispatchQueue.global().async {
                    if gate.wait(timeout: .now() + 10) == .success {
                        self.finish(url: url, status: status, body: body)
                    } else if !self.stateLock.withLock({ self.stopped }) {
                        self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                    }
                }
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
    }

    nonisolated private func finish(url: URL, status: Int, body: Data) {
        guard !stateLock.withLock({ stopped }) else { return }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"],
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func bodyBytes(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { return data }
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
