import Foundation
import os.log

final class StorageService {
    static let shared = StorageService()

    private static let logger = Logger(subsystem: "com.chatbuddy", category: "StorageService")
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
    private static let decoder = JSONDecoder()

    enum ImportValidationError: LocalizedError {
        case keyNotAllowed(String)
        case payloadTooLarge(key: String, size: Int, max: Int)
        case totalPayloadTooLarge(size: Int, max: Int)

        var errorDescription: String? {
            switch self {
            case .keyNotAllowed(let key):
                return "Import contains unsupported storage key: \(key)"
            case .payloadTooLarge(let key, let size, let max):
                return "Import payload for key \(key) is too large (\(size) bytes, max \(max))."
            case .totalPayloadTooLarge(let size, let max):
                return "Import payload is too large (\(size) bytes, max \(max))."
            }
        }
    }

    static let allowedImportKeys: Set<String> = [
        "accentColor",
        "apiConfig",
        "apiProfiles",
        "backgrounds",
        "bookmarks",
        "chatSessions",
        "drafts",
        "friends.groups",
        "friends.meta",
        "intimacy",
        "knowledgeBase",
        "knowledgeGraph.custom",
        "memories",
        "moments",
        "personas.custom",
        "social",
        "userProfile",
    ]

    static let maxImportItemBytes = 2 * 1024 * 1024
    static let maxImportTotalBytes = 20 * 1024 * 1024

    private let defaults: UserDefaults
    private let prefix = "chat-buddy:"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func get<T: Codable>(_ key: String, default defaultValue: T) -> T {
        let fullKey = prefixedKey(key)
        guard let data = defaults.data(forKey: fullKey) else { return defaultValue }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            Self.logger.error("Error decoding key \"\(key)\": \(error.localizedDescription)")
            return defaultValue
        }
    }

    func get<T: Codable>(_ key: String) -> T? {
        let fullKey = prefixedKey(key)
        guard let data = defaults.data(forKey: fullKey) else { return nil }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            Self.logger.error("Error decoding key \"\(key)\": \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func set<T: Codable>(_ key: String, value: T) -> Bool {
        let fullKey = prefixedKey(key)
        do {
            let data = try Self.encoder.encode(value)
            defaults.set(data, forKey: fullKey)
            return true
        } catch {
            Self.logger.error("Error encoding key \"\(key)\": \(error.localizedDescription)")
            return false
        }
    }

    /// Asynchronous save — encodes off the main thread for large payloads.
    /// The caller should use this when persisting large collections (e.g. chatSessions).
    func setAsync<T: Codable>(_ key: String, value: T) {
        let fullKey = prefixedKey(key)
        let defaultsRef = defaults
        Task.detached(priority: .utility) {
            do {
                let data = try Self.encoder.encode(value)
                await MainActor.run {
                    defaultsRef.set(data, forKey: fullKey)
                }
            } catch {
                Self.logger.error("Error encoding key \"\(key)\" async: \(error.localizedDescription)")
            }
        }
    }

    func remove(_ key: String) {
        defaults.removeObject(forKey: prefixedKey(key))
    }

    func clear() {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    func exportAll() -> [String: Data] {
        var result: [String: Data] = [:]
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(prefix) {
            if let data = defaults.data(forKey: key) {
                let shortKey = String(key.dropFirst(prefix.count))
                result[shortKey] = data
            }
        }
        return result
    }

    func importAll(_ data: [String: Data]) -> Int {
        do {
            return try importAllValidated(data)
        } catch {
            Self.logger.error("Import rejected: \(error.localizedDescription)")
            return 0
        }
    }

    @discardableResult
    func importAllValidated(_ data: [String: Data]) throws -> Int {
        var count = 0
        var totalBytes = 0
        for (key, value) in data {
            guard Self.allowedImportKeys.contains(key) else {
                throw ImportValidationError.keyNotAllowed(key)
            }
            guard value.count <= Self.maxImportItemBytes else {
                throw ImportValidationError.payloadTooLarge(
                    key: key,
                    size: value.count,
                    max: Self.maxImportItemBytes
                )
            }
            totalBytes += value.count
            guard totalBytes <= Self.maxImportTotalBytes else {
                throw ImportValidationError.totalPayloadTooLarge(
                    size: totalBytes,
                    max: Self.maxImportTotalBytes
                )
            }
            defaults.set(value, forKey: prefixedKey(key))
            count += 1
        }
        return count
    }

    private func prefixedKey(_ key: String) -> String {
        key.hasPrefix(prefix) ? key : "\(prefix)\(key)"
    }
}
