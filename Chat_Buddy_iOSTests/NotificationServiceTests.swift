import XCTest
@testable import Chat_Buddy_iOS

final class NotificationServiceTests: XCTestCase {

    private var service: NotificationService!

    override func setUp() {
        super.setUp()
        service = NotificationService()
        // Clear unread counts for clean tests
        service.clearUnread("test-chat-1")
        service.clearUnread("test-chat-2")
    }

    // MARK: - Unread Counts

    func testInitialUnreadIsZero() {
        XCTAssertEqual(service.getUnreadCount("fresh-chat"), 0)
    }

    func testIncrementUnread() {
        service.incrementUnread("test-chat-1")
        XCTAssertEqual(service.getUnreadCount("test-chat-1"), 1)

        service.incrementUnread("test-chat-1")
        XCTAssertEqual(service.getUnreadCount("test-chat-1"), 2)
    }

    func testClearUnread() {
        service.incrementUnread("test-chat-1")
        service.incrementUnread("test-chat-1")
        service.clearUnread("test-chat-1")
        XCTAssertEqual(service.getUnreadCount("test-chat-1"), 0)
    }

    func testMarkChatUnread() {
        service.markChatUnread("test-chat-1")
        XCTAssertEqual(service.getUnreadCount("test-chat-1"), 1)
    }

    func testTotalUnread() {
        service.incrementUnread("test-chat-1")
        service.incrementUnread("test-chat-1")
        service.incrementUnread("test-chat-2")
        XCTAssertEqual(service.totalUnread, 3)
    }

    // MARK: - Settings

    func testToggleSound() {
        let initial = service.settings.soundEnabled
        service.toggleSound()
        XCTAssertNotEqual(service.settings.soundEnabled, initial)
    }

    func testToggleDoNotDisturb() {
        let initial = service.settings.doNotDisturb
        service.toggleDoNotDisturb()
        XCTAssertNotEqual(service.settings.doNotDisturb, initial)
        // Reset
        service.toggleDoNotDisturb()
    }

    func testNotifyDoNotDisturbSilent() {
        // In DND mode, should not crash even though it doesn't play sound
        if !service.settings.doNotDisturb { service.toggleDoNotDisturb() }
        service.notify(chatId: "test-chat-1")
        // Just verify no crash; unread should still increment
        XCTAssertGreaterThan(service.getUnreadCount("test-chat-1"), 0)
        // Reset DND
        if service.settings.doNotDisturb { service.toggleDoNotDisturb() }
    }
}
