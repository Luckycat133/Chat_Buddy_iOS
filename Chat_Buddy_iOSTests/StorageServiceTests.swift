import XCTest
@testable import Chat_Buddy_iOS

final class StorageServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var storage: StorageService!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: #function)!
        storage = StorageService(defaults: defaults)
        defaults.removePersistentDomain(forName: #function)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: #function)
        super.tearDown()
    }

    // MARK: - Basic CRUD

    func testSetAndGetString() {
        storage.set("testKey", value: "Hello")
        let result: String? = storage.get("testKey")
        XCTAssertEqual(result, "Hello")
    }

    func testGetDefaultValue() {
        let result = storage.get("nonexistent", default: "default")
        XCTAssertEqual(result, "default")
    }

    func testGetStruct() {
        let config = APIConfig.default
        storage.set("config", value: config)
        let loaded: APIConfig? = storage.get("config")
        XCTAssertEqual(loaded?.baseURL, config.baseURL)
        XCTAssertEqual(loaded?.model, config.model)
    }

    func testGetArray() {
        let array = ["a", "b", "c"]
        storage.set("array", value: array)
        let loaded: [String]? = storage.get("array")
        XCTAssertEqual(loaded?.count, 3)
        XCTAssertEqual(loaded?.first, "a")
    }

    func testGetDictionary() {
        let dict = ["key1": "value1", "key2": "value2"]
        storage.set("dict", value: dict)
        let loaded: [String: String]? = storage.get("dict")
        XCTAssertEqual(loaded?.count, 2)
    }

    func testRemove() {
        storage.set("toRemove", value: "value")
        storage.remove("toRemove")
        let result: String? = storage.get("toRemove")
        XCTAssertNil(result)
    }

    func testOverwriteValue() {
        storage.set("key", value: "first")
        storage.set("key", value: "second")
        let result: String? = storage.get("key")
        XCTAssertEqual(result, "second")
    }

    // MARK: - Encoding / Decoding

    func testCodableStructRoundTrip() {
        let profile = APIProfile(name: "Test Profile", config: APIConfig.default)
        storage.set("profile", value: profile)
        let loaded: APIProfile? = storage.get("profile")
        XCTAssertEqual(loaded?.name, profile.name)
        XCTAssertEqual(loaded?.config.model, profile.config.model)
    }

    func testCodableArrayRoundTrip() {
        let sessions = [
            ChatSession(personaId: "p1"),
            ChatSession(personaId: "p2")
        ]
        storage.set("sessions", value: sessions)
        let loaded: [ChatSession]? = storage.get("sessions")
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?[0].primaryPersonaId, "p1")
        XCTAssertEqual(loaded?[1].primaryPersonaId, "p2")
    }

    func testNestedCodableRoundTrip() {
        let session = ChatSession(personaId: "test-persona")
        session.messages.append(ChatMessage(role: .user, content: "Hello"))
        let poll = ChatPoll(question: "Q?", options: [ChatPollOption(text: "A"), ChatPollOption(text: "B")])
        session.polls.append(poll)
        storage.set("session", value: session)
        let loaded: ChatSession? = storage.get("session")
        XCTAssertEqual(loaded?.messages.count, 1)
        XCTAssertEqual(loaded?.polls.count, 1)
        XCTAssertEqual(loaded?.polls.first?.question, "Q?")
    }

    func testInvalidDataReturnsDefault() {
        defaults.set("invalid".data(using: .utf8), forKey: "chat-buddy:invalidKey")
        let result = storage.get("invalidKey", default: "fallback")
        XCTAssertEqual(result, "fallback")
    }

    // MARK: - Import / Export

    func testExportAll() {
        storage.set("key1", value: "value1")
        storage.set("key2", value: "value2")
        let exported = storage.exportAll()
        XCTAssertFalse(exported.isEmpty)
        XCTAssertTrue(exported.keys.contains("key1") || exported.keys.contains("key2"))
    }

    func testImportAll() {
        let data: [String: Data] = [
            "apiConfig": try! JSONEncoder().encode(APIConfig.default)
        ]
        let count = storage.importAll(data)
        XCTAssertEqual(count, 1)
    }

    func testImportAllRejectsDisallowedKey() {
        let data: [String: Data] = [
            "disallowedKey": "value".data(using: .utf8)!
        ]
        let count = storage.importAll(data)
        XCTAssertEqual(count, 0)
    }

    func testImportAllValidatesAllowedKeys() {
        let data: [String: Data] = [
            "apiConfig": try! JSONEncoder().encode(APIConfig.default),
            "chatSessions": try! JSONEncoder().encode([ChatSession]())
        ]
        let count = storage.importAll(data)
        XCTAssertEqual(count, 2)
    }

    func testImportAllValidatedPayloadTooLarge() {
        let largeData = Data(repeating: 0, count: StorageService.maxImportItemBytes + 1)
        let data: [String: Data] = [
            "apiConfig": largeData
        ]
        do {
            _ = try storage.importAllValidated(data)
            XCTFail("Should throw payloadTooLarge error")
        } catch let error as StorageService.ImportValidationError {
            if case .payloadTooLarge = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testImportAllValidatedTotalTooLarge() {
        let data: [String: Data] = [
            "apiConfig": Data(repeating: 0, count: StorageService.maxImportTotalBytes / 2 + 1),
            "chatSessions": Data(repeating: 0, count: StorageService.maxImportTotalBytes / 2 + 1)
        ]
        do {
            _ = try storage.importAllValidated(data)
            XCTFail("Should throw totalPayloadTooLarge error")
        } catch let error as StorageService.ImportValidationError {
            if case .totalPayloadTooLarge = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testImportAllValidatedDisallowedKeyThrows() {
        let data: [String: Data] = [
            "maliciousKey": "value".data(using: .utf8)!
        ]
        do {
            _ = try storage.importAllValidated(data)
            XCTFail("Should throw keyNotAllowed error")
        } catch let error as StorageService.ImportValidationError {
            if case .keyNotAllowed(let key) = error {
                XCTAssertEqual(key, "maliciousKey")
            } else {
                XCTFail("Wrong error case: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testImportAllReturnsCount() {
        let data: [String: Data] = [
            "apiConfig": try! JSONEncoder().encode(APIConfig.default),
            "backgrounds": try! JSONEncoder().encode([ChatBackground]())
        ]
        let count = storage.importAll(data)
        XCTAssertEqual(count, 2)
    }

    // MARK: - Key Prefixing

    func testKeyPrefixing() {
        storage.set("myKey", value: "myValue")
        let stored = defaults.data(forKey: "chat-buddy:myKey")
        XCTAssertNotNil(stored)
    }

    func testGetWithExistingPrefix() {
        let key = "chat-buddy:prefixed"
        defaults.set("test".data(using: .utf8), forKey: key)
        let result: String? = storage.get("prefixed")
        XCTAssertNotNil(result)
    }

    // MARK: - Clear

    func testClearRemovesPrefixedKeys() {
        storage.set("key1", value: "value1")
        storage.set("key2", value: "value2")
        storage.clear()
        let result1: String? = storage.get("key1")
        let result2: String? = storage.get("key2")
        XCTAssertNil(result1)
        XCTAssertNil(result2)
    }

    func testClearPreservesOtherUserDefaultsKeys() {
        defaults.set("nonChatBuddy", forKey: "regularKey")
        storage.clear()
        let regular = defaults.string(forKey: "regularKey")
        XCTAssertEqual(regular, "nonChatBuddy")
    }
}
