import XCTest
@testable import Chat_Buddy_iOS

final class ContextCompressorTests: XCTestCase {

    private func makeMessages(count: Int, role: ChatMessage.Role = .user) -> [ChatMessage] {
        (0..<count).map { i in
            ChatMessage(role: role, content: "Message \(i)")
        }
    }

    // MARK: - Threshold

    func testBelowThresholdNoCompression() {
        let messages = makeMessages(count: 10)
        let result = ContextCompressor.compress(messages: messages, personas: [])
        XCTAssertFalse(result.compressed)
        XCTAssertNil(result.summary)
        XCTAssertEqual(result.recentMessages.count, 10)
    }

    func testAboveThresholdCompresses() {
        let messages = makeMessages(count: 20)
        let result = ContextCompressor.compress(messages: messages, personas: [])
        XCTAssertTrue(result.compressed)
        XCTAssertNotNil(result.summary)
        XCTAssertEqual(result.recentMessages.count, ContextCompressor.recentWindow)
    }

    func testExactThresholdNoCompression() {
        let messages = makeMessages(count: ContextCompressor.compressionThreshold)
        let result = ContextCompressor.compress(messages: messages, personas: [])
        XCTAssertFalse(result.compressed)
    }

    func testOneOverThresholdCompresses() {
        let messages = makeMessages(count: ContextCompressor.compressionThreshold + 1)
        let result = ContextCompressor.compress(messages: messages, personas: [])
        XCTAssertTrue(result.compressed)
    }

    // MARK: - System messages filtered

    func testSystemMessagesNotCounted() {
        var messages = makeMessages(count: 14)
        // Add system messages — these shouldn't count towards threshold
        messages.insert(ChatMessage(role: .system, content: "System prompt"), at: 0)
        messages.insert(ChatMessage(role: .system, content: "Another system"), at: 0)
        let result = ContextCompressor.compress(messages: messages, personas: [])
        // Only 14 visible messages, below threshold
        XCTAssertFalse(result.compressed)
    }

    // MARK: - Summary content

    func testSummaryContainsMessageCount() {
        let messages = makeMessages(count: 20)
        let result = ContextCompressor.compress(messages: messages, personas: [])
        XCTAssertNotNil(result.summary)
        XCTAssertTrue(result.summary?.contains("messages") ?? false)
    }

    // MARK: - Compressed context

    func testCompressedContextBelowThreshold() {
        let messages = makeMessages(count: 10)
        let context = ContextCompressor.compressedContext(messages: messages, personas: [])
        XCTAssertEqual(context.count, 10)
    }

    func testCompressedContextAboveThreshold() {
        let messages = makeMessages(count: 20)
        let context = ContextCompressor.compressedContext(messages: messages, personas: [])
        // Should be 1 summary + recentWindow
        XCTAssertEqual(context.count, ContextCompressor.recentWindow + 1)
        XCTAssertEqual(context.first?.role, .system)
    }

    // MARK: - Recent messages preserved order

    func testRecentMessagesAreLastOnes() {
        let messages = (0..<20).map { i in
            ChatMessage(role: .user, content: "Msg\(i)")
        }
        let result = ContextCompressor.compress(messages: messages, personas: [])
        let lastContent = result.recentMessages.last?.content
        XCTAssertEqual(lastContent, "Msg19")
        let firstRecentContent = result.recentMessages.first?.content
        XCTAssertEqual(firstRecentContent, "Msg12") // 20 - 8 = 12
    }
}
