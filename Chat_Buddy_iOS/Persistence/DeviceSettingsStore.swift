import Foundation
import SwiftData

/// Device-local settings store per skill §"Replace local authority with
/// cache" + IOS_IMPLEMENTATION §3:
///   - small, non-sensitive, device-only preferences (selected tab,
///     diagnostics opt-in, quiet-hours local presentation hint, …)
///   - cloud-authoritative values are NEVER written here
///   - session/refresh secrets stay in Keychain (AuthSession)
///   - legacy UserDefaults full-array persistence is not used
@MainActor
public final class DeviceSettingsStore {
    /// Known keys. Unknown keys round-trip fine; this enum documents the
    /// current surface and keeps callers from typo-ing raw strings.
    public enum Key: String, Sendable {
        case lastSelectedTab
        case diagnosticsEnabled
        case quietHoursPresentationHint
        case legacyImportCompleted
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func read(_ key: String) -> String? {
        let descriptor = FetchDescriptor<CachedDeviceSetting>(
            predicate: #Predicate { $0.key == key },
        )
        return (try? context.fetch(descriptor))?.first?.value
    }

    public func read(_ key: Key) -> String? { read(key.rawValue) }

    public func write(_ key: String, value: String) {
        let now = Date()
        if let existing = try? context.fetch(
            FetchDescriptor<CachedDeviceSetting>(
                predicate: #Predicate { $0.key == key },
            )
        ).first {
            existing.value = value
            existing.updatedAt = now
        } else {
            context.insert(CachedDeviceSetting(key: key, value: value, updatedAt: now))
        }
        try? context.save()
    }

    public func write(_ key: Key, value: String) { write(key.rawValue, value: value) }

    public func writeBool(_ key: Key, value: Bool) {
        write(key.rawValue, value: value ? "true" : "false")
    }

    public func readBool(_ key: Key) -> Bool {
        read(key.rawValue) == "true"
    }

    public func remove(_ key: String) {
        if let existing = try? context.fetch(
            FetchDescriptor<CachedDeviceSetting>(
                predicate: #Predicate { $0.key == key },
            )
        ).first {
            context.delete(existing)
            try? context.save()
        }
    }

    public func removeAll() {
        let rows = (try? context.fetch(FetchDescriptor<CachedDeviceSetting>())) ?? []
        for row in rows { context.delete(row) }
        try? context.save()
    }
}
