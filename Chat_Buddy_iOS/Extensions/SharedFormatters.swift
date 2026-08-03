import Foundation
import os.log

// MARK: - Shared DateFormatters
//
// `DateFormatter` is expensive to construct. Reuse these static instances instead
// of creating new ones inside computed properties or hot paths.
// See AGENTS.md "Common Gotchas" — Avoid creating DateFormatter in computed vars.

extension DateFormatter {
    /// `yyyy-MM-dd` — used for daily task dates, check-in streaks, export filenames, etc.
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// `HH:mm` — short time-only format for chat list / message timestamps.
    static let chatTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// `.medium` date style — e.g. "Jan 5, 2026".
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// `.short` date style — e.g. "1/5/26".
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    /// `.short` time style — e.g. "3:42 PM".
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// `.full` date style — used by the dashboard header.
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
}

// MARK: - Shared JSON Coders
//
// Centralise the three encoder/decoder configurations used across the project
// so callers don't keep reinstantiating them with bespoke settings.

extension JSONEncoder {
    /// Default encoder — no special configuration. Equivalent to `JSONEncoder()`.
    static let `default` = JSONEncoder()

    /// Encoder with ISO-8601 date encoding strategy. Use for any payload that
    /// round-trips `Date` values across the wire or to disk in ISO format.
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Encoder with ISO-8601 dates plus stable, sorted object keys — used for
    /// backup/export files where deterministic output aids diffing.
    static let iso8601Sorted: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()
}

extension JSONDecoder {
    /// Default decoder — no special configuration. Equivalent to `JSONDecoder()`.
    static let `default` = JSONDecoder()

    /// Decoder with ISO-8601 date decoding strategy.
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Logger Subsystem
//
// Centralise the os.Logger subsystem string so it can't drift between files.
// Callers should use `Logger.app(category:)` instead of `Logger(subsystem:category:)`.

extension Logger {
    /// The shared app subsystem used by every `Logger` in the project.
    static let appSubsystem = "com.chatbuddy"

    /// Creates a `Logger` scoped to the app's subsystem with the given category.
    /// - Parameter category: typically the file/type name, e.g. `"StorageService"`.
    static func app(category: String) -> Logger {
        Logger(subsystem: appSubsystem, category: category)
    }
}
