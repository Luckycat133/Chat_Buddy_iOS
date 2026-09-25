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
    public static func make(schema: Schema) throws -> ModelContainer {
        let config = ModelConfiguration(
            "ChatBuddyCloudCache",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
        )
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

    /// Destroy the SwiftData cache store (account deletion path). The
    /// store must be dead by the time the next `CloudAppState` boots, so
    /// delete the on-disk files for the named configuration.
    public static func destroyStore(named name: String) {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        // SwiftData default store layout: <name>.sqlite (+ -wal/-shm).
        for suffix in [".sqlite", ".sqlite-wal", ".sqlite-shm"] {
            let url = support.appendingPathComponent(name + suffix)
            try? fm.removeItem(at: url)
        }
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