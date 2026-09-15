import Foundation
import SwiftData

/// Cursor store backed by SwiftData. The cloud cursor is opaque
/// base64url-encoded `{ "eventId": "uuid", "occurredAt": "iso" }` produced
/// by the server.
@MainActor
public final class SyncCursorStore {
    private let context: ModelContext

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