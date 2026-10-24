import Foundation
import SwiftData

/// Cursor store backed by SwiftData. The cloud cursor is opaque
/// base64url-encoded `{ "eventId": "uuid", "occurredAt": "iso" }` produced
/// by the server.
@MainActor
public final class SyncCursorStore {
    private let context: ModelContext
    /// Non-isolated teardown on purpose — see `LegacyImporter.nonisolated deinit`
    /// for the full story: with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a
    /// `@MainActor` class gets an *isolated* deinit, and releasing such an
    /// instance from a non-main thread makes Swift run the deinit through a
    /// task on the actor's executor, which freed the instance twice
    /// ("malloc: pointer being freed was not allocated", CI runs 40057054236 /
    /// 40059118662). The teardown only releases the SwiftData context, which
    /// does not need the main actor.
    nonisolated deinit {}



    public init(context: ModelContext) {
        self.context = context
    }

    public func readCursor(accountId: String) -> String? {
        let descriptor = FetchDescriptor<CachedSyncCursor>(
            predicate: #Predicate { $0.accountId == accountId },
        )
        return (try? context.fetch(descriptor))?.first?.cursor
    }

    public func writeCursor(accountId: String, cursor: String) {
        if let existing = try? context.fetch(
            FetchDescriptor<CachedSyncCursor>(
                predicate: #Predicate { $0.accountId == accountId },
            )
        ).first {
            existing.cursor = cursor
            existing.updatedAt = Date()
        } else {
            context.insert(
                CachedSyncCursor(
                    accountId: accountId,
                    cursor: cursor,
                    updatedAt: Date(),
                ),
            )
        }
        try? context.save()
    }

    public func clearCursor(accountId: String) {
        let descriptor = FetchDescriptor<CachedSyncCursor>(
            predicate: #Predicate { $0.accountId == accountId },
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            try? context.save()
        }
    }
}