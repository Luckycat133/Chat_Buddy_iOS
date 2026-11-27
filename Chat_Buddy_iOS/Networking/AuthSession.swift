import Foundation
import Security
import os

/// Keychain-backed session store.
///
/// Per skill §"Quality bar":
///   - No model/provider secret is embedded.
///   - Native writes are confirmed and truthful.
/// Per §"Privacy":
///   - Refresh tokens live in Keychain, not UserDefaults.
///
/// `KeychainService` and `APIConfigStore` already use Keychain in the
/// existing codebase; `AuthSession` adds the cloud-fresh token contract.
public actor AuthSession {
    private let keychain: KeychainStore
    private let service: String
    private let environment: AppEnvironment
    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var cachedActorId: String?
    private var cachedAccountId: String?
    private var cachedAccessExpiresAt: Date?
    private var cachedAppleSubject: String?
    private var reloadAllowed = true
    private let logger = CloudLogger.auth

    public init(
        environment: AppEnvironment,
        keychain: KeychainStore = .shared,
        service: String = "com.chatbuddy.ios.auth",
    ) {
        self.environment = environment
        self.keychain = keychain
        self.service = service
    }

    // MARK: Token accessors

    public func currentAccessToken() async -> String? {
        if let cached = cachedAccessToken, let expires = cachedAccessExpiresAt, expires > Date() {
            return cached
        }
        load()
        return cachedAccessToken
    }

    func currentAccessToken(forAccountId accountId: String?) async -> String? {
        if cachedAccessToken == nil { load() }
        guard accountId == nil || cachedAccountId == accountId else { return nil }
        return cachedAccessToken
    }

    public func currentRefreshToken() async -> String? {
        // Load-from-Keychain first when the cache is cold. The former
        // `cachedRefreshToken ?? (await load()).refresh` placed `await`
        // inside an autoclosure, which is a type error.
        if cachedRefreshToken == nil {
            load()
        }
        return cachedRefreshToken
    }
    public func currentActorId() async -> String? { cachedActorId }
    public func currentAccountId() async -> String? { cachedAccountId }

    public func currentSession() async -> SessionSnapshot? {
        if cachedAccessToken == nil { load() }
        guard let access = cachedAccessToken, let refresh = cachedRefreshToken,
              let accountId = cachedAccountId, let actorId = cachedActorId,
              let expiry = cachedAccessExpiresAt
        else { return nil }
        return SessionSnapshot(
            accessToken: access,
            refreshToken: refresh,
            accountId: accountId,
            actorId: actorId,
            accessExpiresAt: expiry,
        )
    }

    public func isAuthenticated() async -> Bool {
        await currentAccessToken() != nil
    }

    // MARK: Token write/clear

    public func update(tokens: AuthTokens) async {
        reloadAllowed = true
        cachedAccessToken = tokens.accessToken
        cachedRefreshToken = tokens.refreshToken
        cachedActorId = tokens.actorId
        cachedAccountId = tokens.accountId
        cachedAccessExpiresAt = tokens.accessExpiresAt
        persist(tokens)
    }

    func applyRefresh(
        previous: SessionSnapshot,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
    ) -> Bool {
        guard reloadAllowed, cachedAccountId == previous.accountId,
              cachedAccessToken == previous.accessToken, cachedRefreshToken == previous.refreshToken
        else { return false }
        cachedAccessToken = accessToken
        cachedAccessExpiresAt = expiresAt
        cachedRefreshToken = refreshToken
        persist(AuthTokens(
            accessToken: accessToken, refreshToken: refreshToken, accountId: previous.accountId,
            actorId: previous.actorId, accessExpiresAt: expiresAt,
        ))
        return true
    }

    @discardableResult
    public func clear() async -> Bool {
        reloadAllowed = false
        cachedAccessToken = nil
        cachedRefreshToken = nil
        cachedActorId = nil
        cachedAccountId = nil
        cachedAccessExpiresAt = nil
        cachedAppleSubject = nil
        var cleared = true
        for account in [accessAccount, appleSubjectAccount] {
            do {
                try keychain.delete(account: account, service: service)
            } catch {
                cleared = false
                logger.error("cloud session Keychain cleanup failed")
            }
        }
        return cleared
    }

    // MARK: Apple subject (separate keychain item — additive, so an
    // existing StoredSession payload keeps decoding across app updates).

    public func storeAppleSubject(_ subject: String) async {
        do {
            try keychain.write(
                account: appleSubjectAccount,
                service: service,
                value: AppleSubjectRecord(subject: subject),
                accessControl: .afterFirstUnlockThisDeviceOnly,
            )
            cachedAppleSubject = subject
        } catch {
            logger.error("apple subject persist failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func activeAppleSubject() async -> String? {
        guard reloadAllowed else { return nil }
        if cachedAppleSubject == nil {
            if let record = try? keychain.read(
                account: appleSubjectAccount,
                service: service,
                as: AppleSubjectRecord.self,
            ) {
                cachedAppleSubject = record.subject
            }
        }
        return cachedAppleSubject
    }

    public func clearAppleSubject() async {
        cachedAppleSubject = nil
        try? keychain.delete(account: appleSubjectAccount, service: service)
    }

    // MARK: Persistence

    private struct StoredSession: Codable {
        let accessToken: String
        let refreshToken: String
        let accountId: String
        let actorId: String
        let accessExpiresAt: Date
    }

    private var accessAccount: String {
        "\(environment.bundleIdentifier).auth.session"
    }

    private var appleSubjectAccount: String {
        "\(environment.bundleIdentifier).auth.appleSubject"
    }

    private struct AppleSubjectRecord: Codable {
        let subject: String
    }

    private func load() {
        guard reloadAllowed else { return }
        do {
            let stored = try keychain.read(account: accessAccount, service: service, as: StoredSession.self)
            cachedAccessToken = stored.accessToken
            cachedRefreshToken = stored.refreshToken
            cachedActorId = stored.actorId
            cachedAccountId = stored.accountId
            cachedAccessExpiresAt = stored.accessExpiresAt
        } catch {
            // Missing or corrupted session — sign-in required.
            logger.notice("auth session load failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func persist(_ tokens: AuthTokens) {
        let stored = StoredSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            accountId: tokens.accountId,
            actorId: tokens.actorId,
            accessExpiresAt: tokens.accessExpiresAt,
        )
        do {
            try keychain.write(
                account: accessAccount,
                service: service,
                value: stored,
                accessControl: .afterFirstUnlockThisDeviceOnly,
            )
        } catch {
            logger.error("auth session persist failed: \(String(describing: error), privacy: .public)")
        }
    }
}

public struct AuthTokens: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let accountId: String
    public let actorId: String
    public let accessExpiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String,
        accountId: String,
        actorId: String,
        accessExpiresAt: Date,
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountId = accountId
        self.actorId = actorId
        self.accessExpiresAt = accessExpiresAt
    }
}

public struct SessionSnapshot: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let accountId: String
    public let actorId: String
    public let accessExpiresAt: Date
}

/// Thin Keychain wrapper around the existing `KeychainService` patterns in
/// the repo. Codable values are JSON-encoded for storage.
public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore()

    private let serviceName: String
    /// Non-isolated teardown on purpose — see `LegacyImporter.nonisolated deinit`.
    /// Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` this type gets an isolated
    /// deinit, so releasing it off the main actor frees the instance twice.
    nonisolated deinit {}

    public init(serviceName: String = "com.chatbuddy.ios") {
        self.serviceName = serviceName
    }

    public enum KeychainError: Error, Sendable {
        case unhandled(OSStatus)
        case decode(String)
        case encode(String)
    }

    public enum AccessControl: Sendable {
        case afterFirstUnlock
        case afterFirstUnlockThisDeviceOnly
        case whenUnlockedThisDeviceOnly
    }

    public func write<Value: Encodable>(
        account: String,
        service: String,
        value: Value,
        accessControl: AccessControl = .afterFirstUnlockThisDeviceOnly,
    ) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibleAttribute(accessControl),
        ]
        let updated = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError.unhandled(updated) }
        let attributes = query.merging(update) { _, value in value }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    public func read<Value: Decodable>(
        account: String,
        service: String,
        as _: Value.Type,
    ) throws -> Value {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
        guard let data = item as? Data else {
            throw KeychainError.decode("missing data")
        }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw KeychainError.decode(String(describing: error))
        }
    }

    public func delete(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func accessibleAttribute(_ mode: AccessControl) -> CFString {
        switch mode {
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}
