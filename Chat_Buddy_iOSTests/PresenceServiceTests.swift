import XCTest
@testable import Chat_Buddy_iOS

final class PresenceServiceTests: XCTestCase {

    // MARK: - Status Enum

    func testAllStatusesHaveIcons() {
        for status in PresenceService.Status.allCases {
            XCTAssertFalse(status.icon.isEmpty)
        }
    }

    func testAllStatusesHaveColors() {
        for status in PresenceService.Status.allCases {
            XCTAssertTrue(status.color.hasPrefix("#"))
        }
    }

    func testStatusLabels() {
        let online = PresenceService.Status.online
        XCTAssertEqual(online.label(isZh: false), "Online")
        XCTAssertEqual(online.label(isZh: true), "在线")
    }

    // MARK: - Schedule-Based Status

    func testGetStatusReturnsValidStatus() {
        let status = PresenceService.getStatus(for: "ai-luna")
        XCTAssertTrue(PresenceService.Status.allCases.contains(status))
    }

    func testGetStatusForUnknownPersona() {
        let status = PresenceService.getStatus(for: "nonexistent-persona-xyz")
        // Unknown persona should still return a valid status (default schedule)
        XCTAssertTrue(PresenceService.Status.allCases.contains(status))
    }

    func testGetStatusForMultiplePersonas() {
        let personaIds = ["ai-luna", "ai-rem", "ai-naruto", "ai-l", "ai-zerotwo", "ai-gojo"]
        for id in personaIds {
            let status = PresenceService.getStatus(for: id)
            XCTAssertTrue(PresenceService.Status.allCases.contains(status))
        }
    }

    // MARK: - Status Description

    func testStatusLabelNotEmpty() {
        let status = PresenceService.getStatus(for: "ai-luna")
        XCTAssertFalse(status.label(isZh: false).isEmpty)
        XCTAssertFalse(status.label(isZh: true).isEmpty)
    }

    func testGetPresenceMap() {
        let ids = ["ai-luna", "ai-rem", "ai-naruto"]
        let map = PresenceService.getPresenceMap(personaIds: ids)
        XCTAssertEqual(map.count, 3)
        for id in ids {
            XCTAssertNotNil(map[id])
        }
    }
}
