import Foundation
import Security

/// Thin wrapper around the iOS Keychain for storing sensitive string values.
/// Used to persist API keys instead of UserDefaults.
enum KeychainService {
    private static let service = "com.chatbuddy.ios"

    /// Stores `value` under `key`. Overwrites any existing entry.
    @discardableResult
    static func set(_ key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service
        ]
        // Remove any existing item first so we can add fresh.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = data
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Returns the stored value for `key`, or `nil` if not found.
    static func get(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Removes the entry for `key`. Silently ignored if not present.
    static func delete(_ key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
