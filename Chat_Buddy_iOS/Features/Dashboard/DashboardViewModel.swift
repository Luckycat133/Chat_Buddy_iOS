import SwiftUI

@Observable
final class DashboardViewModel {

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
