import XCTest
import SwiftData
@testable import Chat_Buddy_iOS

@MainActor
final class DeviceSettingsStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: DeviceSettingsStore!

    override func setUp() async throws {
        try super.setUp()
        container = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        store = DeviceSettingsStore(context: ModelContext(container))
    }

    override func tearDown() async throws {
        store = nil
        container = nil
        try await super.tearDown()
    }

    func testWriteThenReadRoundTrips() {
        store.write(.lastSelectedTab, value: "moments")
        XCTAssertEqual(store.read(.lastSelectedTab), "moments")
    }

    func testOverwriteUpdatesInPlaceWithoutDuplicates() throws {
        store.write(.lastSelectedTab, value: "chats")
        store.write(.lastSelectedTab, value: "contacts")
        XCTAssertEqual(store.read(.lastSelectedTab), "contacts")
        let rows = try container.mainContext.fetch(FetchDescriptor<CachedDeviceSetting>())
        XCTAssertEqual(rows.count, 1)
    }

    func testBoolConvenience() {
        store.writeBool(.diagnosticsEnabled, value: true)
        XCTAssertTrue(store.readBool(.diagnosticsEnabled))
        store.writeBool(.diagnosticsEnabled, value: false)
        XCTAssertFalse(store.readBool(.diagnosticsEnabled))
    }

    func testRemoveAndRemoveAll() {
        store.write(.lastSelectedTab, value: "chats")
        store.write(.legacyImportCompleted, value: "true")
        store.remove(Key.lastSelectedTab.rawValue)
        XCTAssertNil(store.read(.lastSelectedTab))
        XCTAssertNotNil(store.read(.legacyImportCompleted))
        store.removeAll()
        XCTAssertNil(store.read(.legacyImportCompleted))
    }

    func testRawStringKeysRoundTrip() {
        // Unknown/future keys still persist — the store is schemaless.
        store.write("future.key", value: "v1")
        XCTAssertEqual(store.read("future.key"), "v1")
    }

    func testCloudStateRestoresAndPersistsSelectedTab() throws {
        store.write(.lastSelectedTab, value: "moments")
        let app = try CloudAppState(container: container)
        XCTAssertEqual(app.selectedTab, .moments)

        app.selectedTab = .contacts
        XCTAssertEqual(store.read(.lastSelectedTab), "contacts")
    }
}
