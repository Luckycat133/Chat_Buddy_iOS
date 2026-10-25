import SwiftUI

@Observable
final class DashboardViewModel {
    /// Non-isolated teardown on purpose — see `LegacyImporter.nonisolated deinit`.
    /// Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` this type gets an isolated
    /// deinit, so releasing it off the main actor frees the instance twice.
    nonisolated deinit {}

    /// Time-based greeting key for the current hour.
    var greetingKey: String {
        switch Date.currentHour {
        case 0..<5:  return "greeting_late_night"
        case 5..<12: return "greeting_morning"
        case 12..<18: return "greeting_afternoon"
        default:     return "greeting_evening"
        }
    }

    /// Formatted date string for the greeting header.
    var dateString: String {
        DateFormatter.fullDate.string(from: Date())
    }

    /// Today's featured persona — stable within a calendar day.
    var todaysPick: Persona {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = dayOfYear % PersonaStore.socialCompanions.count
        return PersonaStore.socialCompanions[index]
    }
}
