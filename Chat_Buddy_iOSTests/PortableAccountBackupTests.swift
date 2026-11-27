import Foundation
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
        XCTAssertEqual(backup.localChats.first?.messages.first?.content, "本地消息")
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
            .response(200, Data(#"{"sha256":"fixture-checksum","updated":true}"#.utf8)),
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
        let client = HTTPClient(environment: environment,
                                session: AuthSession(environment: environment, service: "backup-fixture.\(UUID().uuidString)"),
                                urlSession: session)
        let service = PortableAccountBackupService(http: client)
        let receipt = try await service.restore(PortableAccountBackup(document: bytes))
        XCTAssertTrue(receipt.updated)
        let stored = try await service.read(live: false)
        let live = try await service.read(live: true)
        XCTAssertEqual(stored.document, bytes)
        XCTAssertEqual(stored.attachments.first?.verifiedInlineBytes, live.attachments.first?.verifiedInlineBytes)
        XCTAssertEqual(stored.account?.conversations.first?.messages.last?.replyToMessageId, "cloud-message-1")
        XCTAssertEqual(live.document, bytes)
        XCTAssertEqual(script.requests.map(\.method), ["PUT", "GET", "GET"])
        XCTAssertEqual(script.requests.map(\.path), ["/v1/account/backup", "/v1/account/backup", "/v1/account/backup/live"])
        let uploaded = try XCTUnwrap(JSONSerialization.jsonObject(with: script.requests[0].body) as? [String: String])
        XCTAssertEqual(Data(try XCTUnwrap(uploaded["document"]).utf8), bytes)
    }
}
