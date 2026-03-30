import Foundation

/// UserDefaults wrapper with namespace prefix, mirroring the web StorageService.
final class StorageService {
    static let shared = StorageService()

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

    /// Get a Codable value from storage
    func get<T: Codable>(_ key: String, default defaultValue: T) -> T {
        let fullKey = prefixedKey(key)
        guard let data = defaults.data(forKey: fullKey) else { return defaultValue }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[StorageService] Error decoding key \"\(key)\": \(error)")
            return defaultValue
        }
    }

    /// Get an optional Codable value from storage
    func get<T: Codable>(_ key: String) -> T? {
        let fullKey = prefixedKey(key)
        guard let data = defaults.data(forKey: fullKey) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[StorageService] Error decoding key \"\(key)\": \(error)")
            return nil
        }
    }

    /// Save a Codable value to storage
    func set<T: Codable>(_ key: String, value: T) {
        let fullKey = prefixedKey(key)
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: fullKey)
        } catch {
            print("[StorageService] Error encoding key \"\(key)\": \(error)")
        }
    }

    /// Remove a value from storage
    func remove(_ key: String) {
        defaults.removeObject(forKey: prefixedKey(key))
    }

    /// Clear all app-specific keys
    func clear() {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Export all app data as a dictionary
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

    /// Import data from a dictionary
    func importAll(_ data: [String: Data]) -> Int {
        do {
            return try importAllValidated(data)
        } catch {
            print("[StorageService] Import rejected: \(error)")
            return 0
        }
    }

    /// Import data with key + size validation.
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
