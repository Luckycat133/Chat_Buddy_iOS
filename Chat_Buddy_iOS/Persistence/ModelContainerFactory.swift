import CryptoKit
import Foundation
import SwiftData

/// Owns the `ModelContainer` lifecycle. SwiftData on iOS 17+ uses the
/// CloudKit-incompatible local-only container; the cloud runtime is the
/// authoritative source, so this is a strict local cache.
///
/// Per skill §"Replace local authority with cache":
///   - SwiftData replaces UserDefaults arrays.
///   - Keychain holds session; SwiftData holds cache; UserDefaults holds
///     only small preferences.
public enum ModelContainerFactory {
    static func makeAccountStore(
        namespace: String,
        accountId: String,
        storageRoot: URL? = nil,
    ) throws -> ModelContainer {
        let root: URL
        if let storageRoot {
            root = storageRoot
        } else {
            root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true,
            ).appendingPathComponent("ChatBuddyAccounts", isDirectory: true)
        }
        let key = SHA256.hash(data: Data("\(namespace)\u{0}\(accountId)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let directory = root.appendingPathComponent(key, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(
            "AccountCache",
            schema: schema,
            url: directory.appendingPathComponent("cache.store"),
            cloudKitDatabase: .none,
        )
        let destination = try ModelContainer(for: schema, configurations: [config])
        if storageRoot == nil {
            let previous = ModelConfiguration("ChatBuddyCloudCache", schema: schema)
            if FileManager.default.fileExists(atPath: previous.url.path) {
                let legacy = try ModelContainer(for: schema, configurations: [previous])
                try migrateLegacyOutbox(accountId: accountId, from: legacy, to: destination)
            }
        }
        return destination
    }

    /// The former store did not record an owner on most cache rows. Its
    /// per-account outbox is the only data that can be migrated safely.
    @MainActor
    static func migrateLegacyOutbox(accountId: String, from legacy: ModelContainer, to destination: ModelContainer) throws {
        let source = ModelContext(legacy)
        let target = ModelContext(destination)
        let descriptor = FetchDescriptor<OutboxMutation>(predicate: #Predicate { $0.accountId == accountId })
        let pending = try source.fetch(descriptor)
        guard !pending.isEmpty else { return }
        let existing = Dictionary(uniqueKeysWithValues: try target.fetch(descriptor).map { ($0.id, $0) })
        for row in pending {
            if let saved = existing[row.id] {
                guard saved.idempotencyKey == row.idempotencyKey, saved.method == row.method,
                      saved.path == row.path, saved.bodyData == row.bodyData
                else { throw CocoaError(.fileWriteFileExists) }
                continue
            }
            target.insert(OutboxMutation(
                id: row.id, accountId: row.accountId, idempotencyKey: row.idempotencyKey,
                method: row.method, path: row.path, bodyData: row.bodyData, state: row.state,
                attempts: row.attempts, lastError: row.lastError, createdAt: row.createdAt, updatedAt: row.updatedAt,
            ))
        }
        try target.save()
        for row in pending { source.delete(row) }
        try source.save()
    }

    static func makeDeviceSettings() throws -> ModelContainer {
        let schema = Schema([CachedDeviceSetting.self])
        let config = ModelConfiguration("ChatBuddyDeviceSettings", schema: schema, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    public static func makeInMemory(schema: Schema) throws -> ModelContainer {
        let config = ModelConfiguration(
            "ChatBuddyCloudCacheInMemory",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Single source of truth for the cache schema. New models append here.
    public static let schema = Schema([
        CachedActor.self,
        CachedConversation.self,
        CachedConversationMember.self,
        CachedMessage.self,
        CachedMessageBurst.self,
        CachedMoment.self,
        CachedMomentInteraction.self,
        CachedFriendRequest.self,
        CachedRelationship.self,
        CachedGroupInvitation.self,
        CachedMemoryItem.self,
        CachedWorldEvent.self,
        CachedTombstone.self,
        CachedSyncCursor.self,
        OutboxMutation.self,
        CachedDeviceSetting.self,
    ])
}
