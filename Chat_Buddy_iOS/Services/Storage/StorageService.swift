import Foundation

/// UserDefaults wrapper with namespace prefix, mirroring the web StorageService.
final class StorageService {
    static let shared = StorageService()

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
        var count = 0
        for (key, value) in data {
            defaults.set(value, forKey: prefixedKey(key))
            count += 1
        }
        return count
    }

    private func prefixedKey(_ key: String) -> String {
        key.hasPrefix(prefix) ? key : "\(prefix)\(key)"
    }
}
