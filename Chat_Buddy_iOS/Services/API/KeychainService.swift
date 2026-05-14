import Foundation
import Security
import LocalAuthentication

enum KeychainError: LocalizedError {
    case encodingFailed
    case accessControlCreationFailed
    case itemAddFailed(OSStatus)
    case itemUpdateFailed(OSStatus)
    case itemDeleteFailed(OSStatus)
    case itemNotFound
    case unexpectedData
    case biometricNotAvailable
    case biometricFailed
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data"
        case .accessControlCreationFailed:
            return "Failed to create access control"
        case .itemAddFailed(let status):
            return "Failed to add item to keychain: \(status)"
        case .itemUpdateFailed(let status):
            return "Failed to update item in keychain: \(status)"
        case .itemDeleteFailed(let status):
            return "Failed to delete item from keychain: \(status)"
        case .itemNotFound:
            return "Item not found in keychain"
        case .unexpectedData:
            return "Unexpected data format"
        case .biometricNotAvailable:
            return "Biometric authentication not available"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}

enum KeychainService {
    private static let service = "com.chatbuddy.ios"
    private static let logger = Logger(subsystem: "com.chatbuddy", category: "KeychainService")

    static func set(_ key: String, value: String, requireBiometric: Bool = false) throws {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to encode value for key: \(key)")
            throw KeychainError.encodingFailed
        }

        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        if requireBiometric {
            var error: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                &error
            ) else {
                logger.error("Failed to create access control for biometric protection")
                throw KeychainError.accessControlCreationFailed
            }

            var query = baseQuery
            query[kSecAttrAccessControl] = accessControl
            query[kSecValueData] = data

            SecItemDelete(baseQuery as CFDictionary)

            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                logger.error("Failed to add biometric-protected item: \(status)")
                throw KeychainError.itemAddFailed(status)
            }
        } else {
            SecItemDelete(baseQuery as CFDictionary)

            var query = baseQuery
            query[kSecValueData] = data

            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                logger.error("Failed to add item: \(status)")
                throw KeychainError.itemAddFailed(status)
            }
        }
    }

    static func get(_ key: String, context: LAContext? = nil) throws -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        if let authContext = context {
            query[kSecUseAuthenticationContext] = authContext
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                logger.error("Unexpected data format for key: \(key)")
                throw KeychainError.unexpectedData
            }
            return string

        case errSecItemNotFound:
            return nil

        case errSecAuthFailed, errSecUserCanceled:
            logger.warning("Authentication failed for key: \(key)")
            throw KeychainError.authenticationFailed

        case errSecBiometryNotAvailable, errSecBiometryNotEnrolled:
            logger.warning("Biometric not available for key: \(key)")
            throw KeychainError.biometricNotAvailable

        case errSecBiometryLockout:
            logger.warning("Biometric locked out for key: \(key)")
            throw KeychainError.biometricFailed

        default:
            logger.error("Keychain error for key \(key): \(status)")
            return nil
        }
    }

    static func delete(_ key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete key \(key): \(status)")
            throw KeychainError.itemDeleteFailed(status)
        }
    }

    static func exists(_ key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            kSecReturnData: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func clearAll() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to clear all items: \(status)")
            throw KeychainError.itemDeleteFailed(status)
        }
    }
}
