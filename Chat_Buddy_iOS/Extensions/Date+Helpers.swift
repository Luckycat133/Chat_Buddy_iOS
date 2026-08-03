import Foundation

// MARK: - Date Helpers
//
// Small convenience accessors used across the app. Centralised here to avoid
// ad-hoc `Calendar.current.component(...)` calls scattered through services
// and views.

extension Date {
    /// The hour component (0–23) of this date in the current calendar.
    var hour: Int { Calendar.current.component(.hour, from: self) }

    /// Convenience for "this instant's hour" — replaces `Calendar.current.component(.hour, from: Date())`.
    static var currentHour: Int { Date().hour }

    /// Stable `yyyy-MM-dd` key for this date — used for daily task buckets,
    /// streaks, and Moments background scheduling.
    var dayKey: String { DateFormatter.isoDay.string(from: self) }

    /// Convenience for "today's `yyyy-MM-dd` key".
    static var todayDayKey: String { Date().dayKey }
}
