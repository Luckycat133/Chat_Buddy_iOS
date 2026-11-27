import Foundation
import XCTest
@testable import Chat_Buddy_iOS

@MainActor
final class PortablePreferencesTests: XCTestCase {
    func testSharedWebFixtureRoundTripsWithoutLoss() throws {
        let bundle = Bundle(for: PortablePreferencesTests.self)
        let fixture = try XCTUnwrap(
            bundle.url(forResource: "portable-preferences-v1", withExtension: "json")
            ?? bundle.url(forResource: "portable-preferences-v1", withExtension: "json", subdirectory: "Fixtures")
        )
        let source = try Data(contentsOf: fixture)
        let original = try XCTUnwrap(PortablePreferences.decodeIfPresent(source))
        XCTAssertEqual(original.uiLanguage, "zh")
        XCTAssertEqual(original.themeMode, .dark)
        let encoded = try JSONEncoder().encode(original)
        XCTAssertEqual(try PortablePreferences.decodeIfPresent(encoded), original)
        var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
        invalid["apiKey"] = "fixture-not-a-key"
        XCTAssertThrowsError(try PortablePreferences.decodeIfPresent(JSONSerialization.data(withJSONObject: invalid)))
    }
}
