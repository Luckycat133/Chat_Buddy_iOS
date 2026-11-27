import Foundation
import XCTest
@testable import Chat_Buddy_iOS

@MainActor
final class WebV2ChatArchiveTests: XCTestCase {
    func testReadsActualIndexedDBKVShape() throws {
        let bundle = Bundle(for: WebV2ChatArchiveTests.self)
        let file = try XCTUnwrap(
            bundle.url(forResource: "web-v2-chat-archive", withExtension: "json")
            ?? bundle.url(forResource: "web-v2-chat-archive", withExtension: "json", subdirectory: "Fixtures")
        )
        let archive = try WebV2ChatArchive.decode(Data(contentsOf: file))
        let thread = try XCTUnwrap(archive.threads.first)
        XCTAssertEqual(thread.id, "synthetic-chat")
        XCTAssertEqual(thread.name, "Fixture 聊天")
        XCTAssertEqual(thread.messages.map(\.id), ["first", "second"])
        XCTAssertEqual(thread.messages.map(\.senderID), ["user-me", "fixture-peer"])
        XCTAssertEqual(thread.messages.map(\.content), ["Test hello", "测试回复"])
        XCTAssertEqual(thread.messages.last?.quotedMessageID, "first")
        XCTAssertEqual(thread.messages.last?.timestamp, "2026-11-27T07:59:30.000Z")
    }

    func testLegacyMirrorSupportsMissingIndexedDBAndOptionalFields() throws {
        let data = Data(#"{"_meta":{"app":"Chat Buddy","version":2},"localStorage":{"chat-buddy:chat-buddy-chats":[{"id":"x","messages":[{"id":"m","senderId":"user-me","content":"hello"}]}]}}"#.utf8)
        let thread = try XCTUnwrap(WebV2ChatArchive.decode(data).threads.first)
        XCTAssertEqual(thread.name, "x")
        XCTAssertNil(thread.messages.first?.timestamp)
    }

    func testRejectsUnsupportedVersionAndMalformedAuthoritativeRecord() {
        let wrong = Data(#"{"_meta":{"app":"Chat Buddy","version":3},"localStorage":{}}"#.utf8)
        let malformed = Data(#"{"_meta":{"app":"Chat Buddy","version":2},"localStorage":{"chat-buddy-chats":[{"id":"mirror"}]},"indexedDB":{"chat-buddy-main":{"kv":[{"key":"chat-buddy-chats","value":{}}]}}}"#.utf8)
        XCTAssertThrowsError(try WebV2ChatArchive.decode(wrong))
        XCTAssertThrowsError(try WebV2ChatArchive.decode(malformed))
    }
}
