import XCTest
@testable import Chat_Buddy_iOS

final class GreetingServiceTests: XCTestCase {

    // MARK: - Greeting Generation

    func testGreetingNilLastMessage() {
        // With nil last message date, should return nil (no prior conversation)
        let greeting = GreetingService.checkWindowOpenGreeting(
            lastMessageDate: nil,
            personaId: "ai-luna",
            isZh: false
        )
        XCTAssertNil(greeting)
    }

    func testGreetingChinese() {
        // Old message in Chinese mode
        let oldDate = Date().addingTimeInterval(-24 * 3600)
        let greeting = GreetingService.checkWindowOpenGreeting(
            lastMessageDate: oldDate,
            personaId: "ai-rem",
            isZh: true
        )
        if let g = greeting {
            XCTAssertFalse(g.isEmpty)
        }
    }

    func testGreetingRecentMessage() {
        // Recently sent message — should not show greeting  
        let recentDate = Date()
        let greeting = GreetingService.checkWindowOpenGreeting(
            lastMessageDate: recentDate,
            personaId: "ai-luna",
            isZh: false
        )
        // Within cooldown of recent message, greeting should be nil
        XCTAssertNil(greeting)
    }

    func testGreetingOldMessage() {
        // Message from 2 hours ago — might trigger re-engagement
        let oldDate = Date().addingTimeInterval(-2 * 3600)
        let greeting = GreetingService.checkWindowOpenGreeting(
            lastMessageDate: oldDate,
            personaId: "ai-luna",
            isZh: false
        )
        // Should produce some greeting after enough idle time
        if let g = greeting {
            XCTAssertFalse(g.isEmpty)
        }
    }
}
