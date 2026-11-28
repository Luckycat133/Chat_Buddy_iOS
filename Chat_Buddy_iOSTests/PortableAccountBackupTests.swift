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
        for request in script.requests {
            var query = URLComponents()
            query.query = request.query
            XCTAssertEqual(query.queryItems, [URLQueryItem(name: "rebuild", value: "1")])
        }
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

    func testReadOnlyTimelineRetriesFailedNextPageWithoutDiscardingRows() async throws {
        let id = "11111111-1111-4111-8111-111111111111"
        func page(_ sequences: Range<Int>) throws -> Data {
            let items: [[String: Any]] = sequences.map { sequence in
                ["id": "display-fixture-\(sequence)", "conversationId": id, "senderActorId": "fixture-actor",
                 "sequence": sequence, "clientIdempotencyKey": "fixture-\(sequence)", "kind": "text",
                 "content": "Synthetic \(sequence)", "status": "accepted",
                 "createdAt": "2026-11-27T13:00:00.000Z"]
            }
            return try mergeJSON(["items": items])
        }
        let script = OutboxHTTPStub.Script([
            .response(200, try page(37..<237)), .response(403, Data()),
            .response(200, try page(237..<241)),
        ])
        let (_, url, session) = try await makeMergeService(script)
        defer { OutboxHTTPStub.remove(url); session.invalidateAndCancel() }
        let environment = AppEnvironment(
            apiBaseURL: url, realtimeURL: url, bundleIdentifier: "restore-display-fixture", buildNumber: "1",
            enableDiagnostics: false, apnsEnvironment: .sandbox,
        )
        let auth = AuthSession(environment: environment, service: "restore-display-fixture.\(UUID().uuidString)")
        await auth.update(tokens: AuthTokens(accessToken: "fixture-only", refreshToken: "fixture-refresh",
                                             accountId: "fixture-account", actorId: "fixture-actor",
                                             accessExpiresAt: Date().addingTimeInterval(600)))
        let device = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        let cloud = try CloudAppState(
            environment: environment, auth: auth, deviceContainer: device, urlSession: session,
            enablePush: false, enableRealtime: false,
            makeAccountContainer: { _ in try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema) },
        )
        let model = CloudChatViewModel(conversationId: id, app: cloud, initialMessageCursor: 37)
        await model.load()
        XCTAssertEqual(model.nextRestoreCursor, 237)
        let firstPage = model.rows.map(\.id)
        XCTAssertEqual(firstPage.count, 200)
        await model.loadNextRestorePage()
        XCTAssertEqual(model.rows.map(\.id), firstPage)
        XCTAssertEqual(model.nextRestoreCursor, 237)
        XCTAssertNotNil(model.error)
        await model.loadNextRestorePage()
        XCTAssertNil(model.nextRestoreCursor)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.rows.count, 204)
        XCTAssertEqual(model.rows.last?.id, "display-fixture-240")
        XCTAssertEqual(script.requests.map(\.method), ["GET", "GET", "GET"])
        for (request, expected) in zip(script.requests, [37, 237, 237]) {
            var query = URLComponents()
            query.query = request.query
            XCTAssertTrue(query.queryItems?.contains(URLQueryItem(name: "cursor", value: String(expected))) == true)
        }
    }

    func testRebuildPreviewAndReceiptRejectUnscopedOrChangedRestoration() async throws {
        let backup = try PortableAccountBackup(document: fixture())
        let id = try XCTUnwrap(backup.account?.conversations.first?.id)
        let foreign = "99999999-9999-4999-8999-999999999999"
        let counts = ["conversations": ["insert": 1, "skip": 0, "conflict": 0],
                      "messages": ["insert": 2, "skip": 0, "conflict": 0],
                      "attachments": ["insert": 0, "skip": 0, "conflict": 0]]
        func preview(_ restore: [String], unsupported: [String] = []) throws -> Data {
            try mergeJSON(["archiveSha256": backup.sha256, "previewToken": "restore-lease", "counts": counts,
                           "restoredConversationIds": restore, "unsupportedConversationIds": unsupported])
        }
        func receipt(_ restore: String) throws -> Data {
            try mergeJSON(["archiveSha256": backup.sha256, "counts": counts,
                           "affectedConversationIds": [restore], "affectedConversationStarts": [restore: 1],
                           "restoredConversationIds": [restore], "restoredAt": "2026-11-28T00:00:00.000Z"])
        }
        let script = OutboxHTTPStub.Script([
            .response(200, try preview([foreign])),
            .response(200, try preview([id], unsupported: [id])),
            .response(200, try preview([id])),
            .response(200, try receipt(foreign)),
            .response(200, try preview([id])),
            .response(200, try receipt(id)),
        ])
        let (service, url, session) = try await makeMergeService(script)
        defer { OutboxHTTPStub.remove(url); session.invalidateAndCancel() }
        for _ in 0..<2 {
            do {
                _ = try await service.preview(for: backup)
                XCTFail("Unscoped or contradictory preview must not arm commit")
            } catch let error as PortableBackupMergeService.MergeError {
                XCTAssertEqual(error, .invalidPreview)
            }
        }
        let plan = try await service.preview(for: backup)
        XCTAssertEqual(plan.restoredConversationIds, [id])
        XCTAssertEqual(plan.counts.conversations.insert, 1)
        do {
            _ = try await service.commit(plan, confirmed: false)
            XCTFail("No rebuild request before confirmation")
        } catch let error as PortableBackupMergeService.MergeError {
            XCTAssertEqual(error, .confirmationRequired)
        }
        XCTAssertEqual(script.requests.count, 3)
        do {
            _ = try await service.commit(plan, confirmed: true)
            XCTFail("Receipt must identify the exact confirmed restoration")
        } catch let error as PortableBackupMergeService.MergeError {
            XCTAssertEqual(error, .resultUnconfirmed)
        }
        let fresh = try await service.preview(for: backup)
        let committed = try await service.commit(fresh, confirmed: true)
        XCTAssertEqual(committed.restoredConversationIds, [id])
        XCTAssertEqual(committed.affectedConversationStarts, [id: 1])
        XCTAssertEqual(script.requests.map(\.path), [
            "/v1/account/backup/merge/preview", "/v1/account/backup/merge/preview",
            "/v1/account/backup/merge/preview", "/v1/account/backup/merge/commit",
            "/v1/account/backup/merge/preview", "/v1/account/backup/merge/commit",
        ])
    }

    func testRebuildReadbackKeepsOldTombstoneOnFailureThenRestoresFullReplyChain() async throws {
        let id = "11111111-1111-4111-8111-111111111111"
        let another = "22222222-2222-4222-8222-222222222222"
        let date = "2026-11-28T00:00:00.000Z"
        let summary = try mergeJSON(["items": [["id": id, "type": "direct", "createdAt": date,
                                                "publicName": "Rebuilt fixture", "lastReadSequence": 199]]])
        func page(_ sequences: Range<Int>) throws -> Data {
            let items: [[String: Any]] = sequences.map { seq in
                let actor = seq == 199 ? "fixture-human" : seq == 200 ? "fixture-assistant" : "fixture-system"
                var row: [String: Any] = ["id": "thread-\(seq)", "conversationId": id,
                    "senderActorId": actor, "sequence": seq, "clientIdempotencyKey": "reply-\(seq)",
                    "kind": "text", "content": "Synthetic \(seq)", "status": "accepted", "createdAt": date]
                if seq >= 200 { row["replyToMessageId"] = "thread-\(seq - 1)" }
                return row
            }
            return try mergeJSON(["items": items])
        }
        let first = try page(1..<201)
        let second = try page(201..<202)
        let script = OutboxHTTPStub.Script([
            .response(200, summary), .response(200, first), .response(403, Data()),
            .response(200, summary), .response(200, first), .response(200, second),
            .response(200, summary), .response(200, first), .response(200, second),
        ])
        let (service, url, session) = try await makeMergeService(script)
        defer { OutboxHTTPStub.remove(url); session.invalidateAndCancel() }
        let container = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        let context = ModelContext(container)
        context.insert(CachedTombstone(table: "conversations", rowId: id, deletedAt: Date(timeIntervalSince1970: 20)))
        context.insert(CachedTombstone(table: "messages", rowId: another, deletedAt: Date(timeIntervalSince1970: 30)))
        context.insert(CachedConversationMember(conversationId: id, actorId: "fixture-human", status: "active",
            role: "member", invitedByActorId: nil, joinedAt: nil, leftAt: nil, lastReadSequence: 900))
        context.insert(CachedMessage(id: "obsolete-cache-only", conversationId: id,
            senderActorId: "fixture-human", sequence: 900, clientIdempotencyKey: "queued-key",
            kind: "text", content: "An obsolete cached row", structuredPayload: nil,
            replyToMessageId: nil, burstId: nil, status: "accepted", createdAt: .distantPast, deletedAt: nil))
        context.insert(OutboxMutation(id: "queued-row", accountId: "fixture-account",
            idempotencyKey: "queued-key", method: "POST", path: "/v1/conversations/\(id)/messages",
            bodyData: Data(), state: "queued", attempts: 0, lastError: nil,
            createdAt: .distantPast, updatedAt: .distantPast))
        try context.save()
        let repository = ConversationRepository(http: service.http, context: context,
            outbox: OutboxStore(context: context), accountIdProvider: { "fixture-account" })
        let receipt = PortableBackupMergeService.Receipt(archiveSha256: "fixture",
            counts: .init(conversations: .init(insert: 1, skip: 0, conflict: 0),
                          messages: .init(insert: 201, skip: 0, conflict: 0),
                          attachments: .init(insert: 0, skip: 0, conflict: 0)),
            affectedConversationIds: [id], affectedConversationStarts: [id: 1],
            restoredConversationIds: [id], restoredAt: Date(timeIntervalSince1970: 30))
        try await repository.retainArchiveReadback(receipt)
        do {
            try await repository.reconcileRetainedArchiveReadback(myActorId: "fixture-human")
            XCTFail("Incomplete authoritative reply paging must not reveal a rebuilt chat")
        } catch {}
        let firstVisibleList = await repository.cachedConversationList(myActorId: "fixture-human")
        XCTAssertTrue(firstVisibleList.isEmpty)
        let beforeRead = await repository.cachedMessages(conversationId: id)
        XCTAssertTrue(beforeRead.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedMessage>()).map(\.id), ["obsolete-cache-only"])
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<CachedTombstone>()).map(\.rowId)), Set([id, another]))

        try await repository.reconcileRetainedArchiveReadback(myActorId: "fixture-human")
        try await repository.retainArchiveReadback(receipt)
        try await repository.reconcileRetainedArchiveReadback(myActorId: "fixture-human")
        let visible = await repository.cachedConversationList(myActorId: "fixture-human")
        XCTAssertEqual(visible.map(\.id), [id])
        XCTAssertEqual(visible.first?.publicName, "Rebuilt fixture")
        XCTAssertEqual(visible.first?.unreadCount, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedConversationMember>()).first?.lastReadSequence, 199)
        let rows = await repository.cachedMessages(conversationId: id)
        XCTAssertEqual(rows.count, 201)
        XCTAssertEqual(rows.suffix(3).map(\.senderActorId), ["fixture-human", "fixture-assistant", "fixture-system"])
        XCTAssertEqual(rows.suffix(2).map(\.replyToMessageId), ["thread-199", "thread-200"])
        XCTAssertEqual(rows.suffix(2).map(ChatRowModel.fromServer).map(\.replyToMessageId), ["thread-199", "thread-200"])
        XCTAssertFalse(rows.contains { $0.id == "obsolete-cache-only" })
        XCTAssertEqual(try context.fetch(FetchDescriptor<OutboxMutation>()).map(\.id), ["queued-row"])
        XCTAssertEqual(try EventApplier.deletedConversationIDs(in: context), [])
        XCTAssertTrue(try context.fetch(FetchDescriptor<CachedTombstone>()).contains { $0.rowId == another })
        XCTAssertEqual(script.requests.map(\.method), Array(repeating: "GET", count: 9))

        func applyDeletions(_ events: [(String, TimeInterval)]) throws {
            let envelope = SyncCoordinator.ServerEnvelope(cursor: "fixture-cursor", upserts: [],
                tombstones: events.map { SyncTombstone(table: "conversations", id: $0.0,
                    deletedAt: Date(timeIntervalSince1970: $0.1)) },
                serverTime: .distantPast, hasMore: false)
            _ = try EventApplier.apply(envelope: envelope, in: context)
        }
        try applyDeletions([(id, 20), (another, 25)])
        XCTAssertEqual(try EventApplier.deletedConversationIDs(in: context), Set([another]))
        let afterReplay = await repository.cachedMessages(conversationId: id)
        XCTAssertEqual(afterReplay.count, 201)
        try applyDeletions([(id, 40)])
        XCTAssertEqual(try EventApplier.deletedConversationIDs(in: context), Set([id, another]))
        let afterNewDeletion = await repository.cachedMessages(conversationId: id)
        XCTAssertTrue(afterNewDeletion.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OutboxMutation>()).map(\.id), ["queued-row"])
    }

    func testOnlyObservedConversationTombstoneCanBeCleared() throws {
        let id = "11111111-1111-4111-8111-111111111111"
        let other = "22222222-2222-4222-8222-222222222222"
        let date = Date(timeIntervalSince1970: 20)
        let container = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        let context = ModelContext(container)
        let deleted = CachedTombstone(table: "conversations", rowId: id, deletedAt: date)
        context.insert(deleted)
        try context.save()
        let old = try EventApplier.archiveRestoreFence(conversationId: id, in: context)
        let summary = ConversationRepository.ConversationListItem(
            id: id, type: "direct", publicName: "Archived direct", unreadCount: 0,
            lastMessagePreview: nil, lastActivityAt: date, lastReadSequence: 0)
        deleted.deletedAt = date.addingTimeInterval(10)
        try context.save()
        XCTAssertThrowsError(try EventApplier.cacheArchiveMergeRows(conversationId: id, summary: summary,
            messages: [], myActorId: "fixture", in: context, restoration: old))
        XCTAssertThrowsError(try EventApplier.cacheArchiveMergeRows(conversationId: other, summary: summary,
            messages: [], myActorId: "fixture", in: context, restoration: old))
        try EventApplier.cacheArchiveMergeRows(conversationId: id, summary: summary,
            messages: [], myActorId: "fixture", in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CachedConversation>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedTombstone>()).first?.deletedAt, date.addingTimeInterval(10))
    }

    func testConfirmedReconciliationRetriesReadOnlyAfterAccountStoreReopen() async throws {
        let id = "11111111-1111-4111-8111-111111111111"
        let date = "2026-11-28T00:00:00.000Z"
        let summary = try mergeJSON(["items": [["id": id, "type": "direct", "createdAt": date, "lastReadSequence": 0]]])
        let body = try mergeJSON(["archiveSha256": "fixture", "counts": [
            "conversations": ["insert": 1, "skip": 0, "conflict": 0],
            "messages": ["insert": 0, "skip": 0, "conflict": 0],
            "attachments": ["insert": 0, "skip": 0, "conflict": 0],
        ], "affectedConversationIds": [id], "affectedConversationStarts": [id: 1],
            "restoredConversationIds": [id], "restoredAt": "1970-01-01T00:00:30.000Z"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractional
        let receipt = try decoder.decode(PortableBackupMergeService.Receipt.self, from: body)
        let script = OutboxHTTPStub.Script([
            .response(200, summary), .response(403, Data()),
            .response(200, summary), .response(200, try mergeJSON(["items": []])),
        ])
        let (service, url, session) = try await makeMergeService(script)
        defer { OutboxHTTPStub.remove(url); session.invalidateAndCancel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func repository(_ accountId: String) throws -> (ConversationRepository, ModelContext) {
            let store = try ModelContainerFactory.makeAccountStore(namespace: "fixture", accountId: accountId,
                                                                   storageRoot: root)
            let context = ModelContext(store)
            return (ConversationRepository(http: service.http, context: context,
                outbox: OutboxStore(context: context), accountIdProvider: { accountId }), context)
        }
        do {
            let (first, _) = try repository("account-A")
            // This device has not received the old server deletion yet.
            try await first.retainArchiveReadback(receipt)
            do {
                try await first.reconcileRetainedArchiveReadback(myActorId: "fixture")
                XCTFail("First reconciliation should fail")
            } catch {}
            let readbacks = try await first.pendingArchiveReadback()
            XCTAssertEqual(readbacks.map(\.conversationId), [id])
            XCTAssertNil(readbacks.first?.observedDeletion)
            XCTAssertEqual(readbacks.first?.serverDeletionCutoff, Date(timeIntervalSince1970: 30))
        }

        let (otherAccount, _) = try repository("account-B")
        let separate = try await otherAccount.pendingArchiveReadback()
        XCTAssertTrue(separate.isEmpty)
        let (reopened, context) = try repository("account-A")
        let pending = try await reopened.pendingArchiveReadback()
        XCTAssertEqual(pending.first?.conversationId, id)
        try await reopened.reconcileRetainedArchiveReadback(myActorId: "fixture")

        let remaining = try await reopened.pendingArchiveReadback()
        XCTAssertTrue(remaining.isEmpty)
        let restartedChats = await reopened.cachedConversationList(myActorId: "fixture")
        XCTAssertEqual(restartedChats.map(\.id), [id], "An empty rebuilt chat should still be visible")
        XCTAssertTrue(try EventApplier.deletedConversationIDs(in: context).isEmpty)
        for stamp in [20.0, 30.0] {
            let envelope = SyncCoordinator.ServerEnvelope(cursor: "fixture", upserts: [],
                tombstones: [SyncTombstone(table: "conversations", id: id,
                    deletedAt: Date(timeIntervalSince1970: stamp))],
                serverTime: .distantPast, hasMore: false)
            _ = try EventApplier.apply(envelope: envelope, in: context)
            let listed = await reopened.cachedConversationList(myActorId: "fixture")
            XCTAssertEqual(listed.map(\.id), stamp == 20 ? [id] : [],
                "Late older deletion must not hide the restoration; equal timestamp fails closed")
        }
        XCTAssertEqual(script.requests.map(\.method), ["GET", "GET", "GET", "GET"])
        for request in script.requests.filter({ $0.path == "/v1/conversations" }) {
            var query = URLComponents()
            query.query = request.query
            XCTAssertTrue(query.queryItems?.contains(URLQueryItem(name: "ids", value: id)) == true)
        }
        XCTAssertFalse(script.requests.contains { $0.path?.contains("/merge/commit") == true })
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
