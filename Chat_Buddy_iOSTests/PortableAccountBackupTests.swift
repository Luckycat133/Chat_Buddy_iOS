import Foundation
import SwiftData
import CryptoKit
import XCTest
@testable import Chat_Buddy_iOS

@MainActor
final class PortableAccountBackupTests: XCTestCase {
    private func fixture() throws -> Data {
        let bundle = Bundle(for: PortableAccountBackupTests.self)
        let file = try XCTUnwrap(
            bundle.url(forResource: "web-v2-cloud-backup-golden", withExtension: "json")
            ?? bundle.url(forResource: "web-v2-cloud-backup-golden", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: file)
    }

    func testGoldenProjectsLocalAndCloudThreadsAndPreservesAttachmentsAndRawFields() throws {
        let bytes = try fixture()
        let backup = try PortableAccountBackup(document: bytes)
        XCTAssertEqual(backup.document, bytes)
        let local = try XCTUnwrap(backup.localChats.first?.messages.first)
        XCTAssertEqual(local.content, "本地消息")
        XCTAssertEqual(local.senderID, "user-me")
        let localAttachments = backup.attachments(for: local)
        XCTAssertEqual(localAttachments.map(\.id), ["image-local-1", "missing-remote-image"])
        XCTAssertEqual(localAttachments[0].verifiedInlineBytes, backup.attachments[0].verifiedInlineBytes)
        XCTAssertNil(localAttachments[1].verifiedInlineBytes)
        let legacy = try XCTUnwrap(backup.localChats.first?.messages.last)
        XCTAssertEqual(legacy.senderID, "fixture-mira")
        XCTAssertEqual(legacy.quotedMessageID, "local-message-1")
        XCTAssertEqual(backup.attachments(for: legacy).first?.verifiedInlineBytes, localAttachments[0].verifiedInlineBytes)
        XCTAssertEqual(backup.account?.displayName, "合成账户")
        let thread = try XCTUnwrap(backup.account?.conversations.first)
        XCTAssertEqual(thread.lastReadSequence, 2)
        XCTAssertEqual(thread.messages.map(\.content), ["云端消息 1", "云端消息 2"])
        XCTAssertEqual(thread.messages.last?.replyToMessageId, "cloud-message-1")
        let png = try XCTUnwrap(backup.attachments.first?.verifiedInlineBytes)
        XCTAssertEqual(png.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
        XCTAssertEqual(SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
                       "1d4b76d057042b92d4f9ae29eed2ca0ee1f4baa28f17f3e72163aec022273e78")
        XCTAssertEqual(backup.attachments.last?.name, "offline.pdf")
        XCTAssertNil(backup.attachments.last?.verifiedInlineBytes)
        XCTAssertTrue(String(decoding: backup.document, as: UTF8.self).contains("retained"))
    }

    func testRejectsAttachmentLengthMismatchBeforeTransfer() throws {
        let bytes = try fixture()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var attachments = try XCTUnwrap(json["attachments"] as? [[String: Any]])
        attachments[0]["byteLength"] = 1
        json["attachments"] = attachments
        XCTAssertThrowsError(try PortableAccountBackup(document: JSONSerialization.data(withJSONObject: json)))
    }

    func testActualHTTPClientImportsAndRedownloadsByteIdenticalGolden() async throws {
        let bytes = try fixture()
        let script = OutboxHTTPStub.Script([
            .response(200, try JSONSerialization.data(withJSONObject: ["sha256": PortableAccountBackup(document: bytes).sha256, "updated": true])),
            .response(401, Data(#"{"error":{"code":"UNAUTHORIZED","message":"fixture expired"}}"#.utf8)),
            .response(200, bytes),
            .response(200, bytes),
        ])
        let url = OutboxHTTPStub.install(script)
        defer { OutboxHTTPStub.remove(url) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OutboxHTTPStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let environment = AppEnvironment(
            apiBaseURL: url, realtimeURL: url, bundleIdentifier: "backup-fixture", buildNumber: "1",
            enableDiagnostics: false, apnsEnvironment: .sandbox
        )
        let auth = AuthSession(environment: environment, service: "backup-fixture.\(UUID().uuidString)")
        let expiry = Date().addingTimeInterval(600)
        await auth.update(tokens: AuthTokens(accessToken: "fixture-old", refreshToken: "fixture-refresh",
                                             accountId: "fixture-account", actorId: "fixture-person", accessExpiresAt: expiry))
        let client = HTTPClient(environment: environment, session: auth, urlSession: session)
        await client.setUnauthorizedHandler { rejected in
            guard rejected == "fixture-old" else { return false }
            await auth.update(tokens: AuthTokens(accessToken: "fixture-new", refreshToken: "fixture-refresh",
                                                 accountId: "fixture-account", actorId: "fixture-person", accessExpiresAt: expiry))
            return true
        }
        let service = PortableAccountBackupService(http: client)
        let receipt = try await service.restore(PortableAccountBackup(document: bytes))
        XCTAssertTrue(receipt.updated)
        let stored = try await service.read(live: false)
        let live = try await service.read(live: true)
        XCTAssertEqual(stored.document, bytes)
        XCTAssertEqual(stored.attachments.first?.verifiedInlineBytes, live.attachments.first?.verifiedInlineBytes)
        XCTAssertEqual(stored.account?.conversations.first?.messages.last?.replyToMessageId, "cloud-message-1")
        XCTAssertEqual(live.document, bytes)
        XCTAssertEqual(receipt.sha256, stored.sha256)
        XCTAssertEqual(receipt.sha256, live.sha256)
        XCTAssertEqual(script.requests.map(\.authorization), ["Bearer fixture-old", "Bearer fixture-old", "Bearer fixture-new", "Bearer fixture-new"])
        XCTAssertEqual(script.requests.map(\.method), ["PUT", "GET", "GET", "GET"])
        XCTAssertEqual(script.requests.map(\.path), ["/v1/account/backup", "/v1/account/backup", "/v1/account/backup", "/v1/account/backup/live"])
        let uploaded = try XCTUnwrap(JSONSerialization.jsonObject(with: script.requests[0].body) as? [String: String])
        XCTAssertEqual(Data(try XCTUnwrap(uploaded["document"]).utf8), bytes)
    }

    func testMergePreviewCannotWriteAndConfirmSendsOnlyReviewedToken() async throws {
        let bytes = try fixture()
        let backup = try PortableAccountBackup(document: bytes)
        let id = "11111111-1111-4111-8111-111111111111"
        let changed = ["insert": 1, "skip": 1, "conflict": 1]
        let stable = ["insert": 0, "skip": 1, "conflict": 0]
        let counts = ["conversations": stable, "messages": changed, "attachments": stable]
        let repeated = ["conversations": stable, "messages": ["insert": 0, "skip": 2, "conflict": 1], "attachments": stable]
        let script = OutboxHTTPStub.Script([
            .response(200, try mergeJSON(["archiveSha256": backup.sha256, "previewToken": "reviewed-plan",
                                         "counts": counts, "conflicts": ["conversations": [], "messages": ["same-id"], "attachments": []]])),
            .response(200, try mergeJSON(["archiveSha256": backup.sha256, "counts": counts,
                                         "affectedConversationIds": [id], "affectedConversationStarts": [id: 37]])),
            .response(200, try mergeJSON(["archiveSha256": backup.sha256, "previewToken": "no-work", "counts": repeated])),
        ])
        let (service, url, session) = try await makeMergeService(script)
        defer { OutboxHTTPStub.remove(url); session.invalidateAndCancel() }
        let plan = try await service.preview(for: backup)
        XCTAssertEqual(plan.counts.messages.insert, 1)
        XCTAssertEqual(plan.conflicts?.messages, ["same-id"])
        XCTAssertEqual(script.requests.count, 1)
        do {
            _ = try await service.commit(plan, confirmed: false)
            XCTFail("Unconfirmed preview must not send a commit")
        } catch let error as PortableBackupMergeService.MergeError {
            XCTAssertEqual(error, .confirmationRequired)
        }
        XCTAssertEqual(script.requests.count, 1)

        let receipt = try await service.commit(plan, confirmed: true)
        XCTAssertEqual(receipt.affectedConversationStarts, [id: 37])
        let again = try await service.preview(for: backup)
        XCTAssertFalse(again.counts.hasInserts)
        do {
            _ = try await service.commit(again, confirmed: true)
            XCTFail("An already merged archive must have no live write")
        } catch let error as PortableBackupMergeService.MergeError {
            XCTAssertEqual(error, .confirmationRequired)
        }
        XCTAssertEqual(script.requests.map(\.path), ["/v1/account/backup/merge/preview", "/v1/account/backup/merge/commit",
                                                      "/v1/account/backup/merge/preview"])
        XCTAssertEqual(script.requests.map(\.method), ["POST", "POST", "POST"])
        XCTAssertEqual(script.requests.map(\.authorization), Array(repeating: "Bearer backup-fixture-token", count: 3))
        let previewBody = try XCTUnwrap(JSONSerialization.jsonObject(with: script.requests[0].body) as? [String: Any])
        let commitBody = try XCTUnwrap(JSONSerialization.jsonObject(with: script.requests[1].body) as? [String: Any])
        XCTAssertTrue(previewBody.isEmpty)
        XCTAssertEqual(Set(commitBody.keys), Set(["previewToken", "confirm"]))
        XCTAssertEqual(commitBody["confirm"] as? Bool, true)
        XCTAssertEqual(commitBody["previewToken"] as? String, "reviewed-plan")
    }

    func testMismatchedArchiveStaleConfirmationAndLostReceiptAreNeverReplayed() async throws {
        let backup = try PortableAccountBackup(document: fixture())
        let counts = ["conversations": ["insert": 0, "skip": 0, "conflict": 0],
                      "messages": ["insert": 1, "skip": 0, "conflict": 0],
                      "attachments": ["insert": 0, "skip": 0, "conflict": 0]]
        func preview(_ sha: String) throws -> Data {
            try mergeJSON(["archiveSha256": sha, "previewToken": "fixture", "counts": counts])
        }
        let script = OutboxHTTPStub.Script([
            .response(200, try preview("other-sha")),
            .response(200, try preview(backup.sha256)),
            .response(409, Data(#"{"error":{"code":"CONFLICT","message":"fixture stale plan"}}"#.utf8)),
            .response(200, try preview(backup.sha256)),
            .timeout,
        ])
        let (service, url, session) = try await makeMergeService(script)
        defer { OutboxHTTPStub.remove(url); session.invalidateAndCancel() }
        do {
            _ = try await service.preview(for: backup)
            XCTFail("A different stored archive cannot arm confirmation")
        } catch let error as PortableBackupMergeService.MergeError {
            XCTAssertEqual(error, .archiveChanged)
        }
        let plan = try await service.preview(for: backup)
        do {
            _ = try await service.commit(plan, confirmed: true)
            XCTFail("A changed live plan must require a fresh preview")
        } catch let error as PortableBackupMergeService.MergeError {
            XCTAssertEqual(error, .stalePreview)
        }
        let refreshed = try await service.preview(for: backup)
        do {
            _ = try await service.commit(refreshed, confirmed: true)
            XCTFail("A lost receipt is not proof of a failed commit")
        } catch let error as PortableBackupMergeService.MergeError {
            XCTAssertEqual(error, .resultUnconfirmed)
        }
        XCTAssertEqual(script.requests.map(\.path), ["/v1/account/backup/merge/preview", "/v1/account/backup/merge/preview",
                                                      "/v1/account/backup/merge/commit", "/v1/account/backup/merge/preview",
                                                      "/v1/account/backup/merge/commit"])
    }

    func testRefreshUsesAuthoritativeStartAndPaginatesWithoutPosting() async throws {
        let id = "11111111-1111-4111-8111-111111111111"
        let date = "2026-11-27T13:00:00.000Z"
        func page(_ sequences: Range<Int>) throws -> Data {
            let items: [[String: Any]] = sequences.map { sequence in
                ["id": "cache-fixture-\(sequence)", "conversationId": id, "senderActorId": "fixture-actor",
                 "sequence": sequence, "clientIdempotencyKey": "fixture-\(sequence)", "kind": "text",
                 "content": "Synthetic", "status": "accepted", "createdAt": date]
            }
            return try mergeJSON(["items": items])
        }
        let script = OutboxHTTPStub.Script([
            .response(200, try mergeJSON(["items": [["id": id, "type": "direct", "createdAt": date,
                                                    "lastReadSequence": 10]]])),
            .response(200, try page(37..<237)),
            .response(200, try page(237..<239)),
        ])
        let (service, url, session) = try await makeMergeService(script)
        defer { OutboxHTTPStub.remove(url); session.invalidateAndCancel() }
        let container = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        let context = ModelContext(container)
        let repository = ConversationRepository(
            http: service.http, context: context, outbox: OutboxStore(context: context),
            accountIdProvider: { "fixture-account" },
        )
        try await repository.refreshArchiveMerge(conversationIds: [id], starts: [id: 37], myActorId: "fixture-actor")
        XCTAssertEqual(script.requests.map(\.method), ["GET", "GET", "GET"])
        XCTAssertEqual(script.requests.map(\.path), ["/v1/conversations", "/v1/conversations/\(id)/messages",
                                                      "/v1/conversations/\(id)/messages"])
        for (request, expected) in zip(script.requests.dropFirst(), [37, 237]) {
            var query = URLComponents()
            query.query = request.query
            let params = query.queryItems ?? []
            XCTAssertTrue(params.contains(URLQueryItem(name: "cursor", value: String(expected))))
            XCTAssertTrue(params.contains(URLQueryItem(name: "limit", value: "200")))
        }
        let cached = await repository.cachedMessages(conversationId: id)
        XCTAssertEqual(cached.map(\.sequence), Array(37..<239))
    }

    private func mergeJSON(_ payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private func makeMergeService(_ script: OutboxHTTPStub.Script) async throws
        -> (PortableBackupMergeService, URL, URLSession) {
        let url = OutboxHTTPStub.install(script)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OutboxHTTPStub.self]
        let session = URLSession(configuration: configuration)
        let environment = AppEnvironment(
            apiBaseURL: url, realtimeURL: url, bundleIdentifier: "backup-merge-fixture", buildNumber: "1",
            enableDiagnostics: false, apnsEnvironment: .sandbox
        )
        let auth = AuthSession(environment: environment, service: "backup-merge-fixture.\(UUID().uuidString)")
        await auth.update(tokens: AuthTokens(accessToken: "backup-fixture-token", refreshToken: "backup-fixture-refresh",
                                             accountId: "fixture-account", actorId: "fixture-actor",
                                             accessExpiresAt: Date().addingTimeInterval(600)))
        return (PortableBackupMergeService(http: HTTPClient(environment: environment, session: auth, urlSession: session)),
                url, session)
    }
}
