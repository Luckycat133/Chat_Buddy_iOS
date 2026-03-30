import Foundation
import SwiftUI

/// Simulates online/offline/busy status for AI personas based on their timezone and schedule.
/// Port of PresenceService.js.
enum PresenceService {

    // MARK: - Status

    enum Status: String, CaseIterable, Codable {
        case online
        case offline
        case busy
        case away
        case doNotDisturb = "do-not-disturb"

        var icon: String {
            switch self {
            case .online:       return "●"
            case .offline:      return "○"
            case .busy:         return "◐"
            case .away:         return "◔"
            case .doNotDisturb: return "⊘"
            }
        }

        var color: String {
            switch self {
            case .online:       return "#4ECDC4"
            case .offline:      return "#94A3B8"
            case .busy:         return "#FB923C"
            case .away:         return "#FBBF24"
            case .doNotDisturb: return "#F87171"
            }
        }

        var swiftUIColor: Color {
            Color(hex: color)
        }

        func label(isZh: Bool) -> String {
            switch self {
            case .online:       return isZh ? "在线" : "Online"
            case .offline:      return isZh ? "离线" : "Offline"
            case .busy:         return isZh ? "忙碌" : "Busy"
            case .away:         return isZh ? "离开" : "Away"
            case .doNotDisturb: return isZh ? "免打扰" : "Do Not Disturb"
            }
        }
    }

    // MARK: - Schedule

    struct TimeRange: Codable {
        let start: Int // hour 0-23
        let end: Int   // hour 0-23
    }

    struct PersonaSchedule: Codable {
        let timezone: String
        let sleep: TimeRange?
        let busy: [TimeRange]?
    }

    // MARK: - Persona Schedules

    /// Default schedules for built-in personas.
    private static let schedules: [String: PersonaSchedule] = [
        "ai-luna":    .init(timezone: "Asia/Shanghai", sleep: .init(start: 23, end: 7), busy: [.init(start: 14, end: 16)]),
        "ai-miku":    .init(timezone: "Asia/Tokyo", sleep: .init(start: 0, end: 8), busy: [.init(start: 19, end: 21)]),
        "ai-rem":     .init(timezone: "Asia/Tokyo", sleep: nil, busy: nil),
        "ai-naruto":  .init(timezone: "Asia/Tokyo", sleep: .init(start: 22, end: 6), busy: [.init(start: 6, end: 8)]),
        "ai-l":       .init(timezone: "Asia/Tokyo", sleep: nil, busy: nil),
        "ai-zerotwo": .init(timezone: "Asia/Tokyo", sleep: .init(start: 1, end: 9), busy: [.init(start: 10, end: 12)]),
        "ai-gojo":    .init(timezone: "Asia/Tokyo", sleep: .init(start: 2, end: 10), busy: [.init(start: 13, end: 15)]),
        "ai-assistant": .init(timezone: "UTC", sleep: nil, busy: nil),
        "ai-coder":   .init(timezone: "America/New_York", sleep: .init(start: 2, end: 10), busy: nil),
        "ai-scholar": .init(timezone: "Europe/London", sleep: .init(start: 0, end: 7), busy: [.init(start: 9, end: 12)]),
        "ai-writer":  .init(timezone: "America/Los_Angeles", sleep: .init(start: 1, end: 9), busy: nil),
        "ai-translator": .init(timezone: "UTC", sleep: nil, busy: nil),
        "ai-coach":   .init(timezone: "America/Chicago", sleep: .init(start: 23, end: 6), busy: [.init(start: 6, end: 8)]),
    ]

    // MARK: - Status Computation

    /// Get the current simulated status for a persona.
    static func getStatus(for personaId: String, userOverride: Status? = nil) -> Status {
        if let override = userOverride, override != .online { return override }

        guard let schedule = schedules[personaId] else { return .online }

        let hour = currentHour(in: schedule.timezone)

        if let sleep = schedule.sleep, isInRange(hour: hour, range: sleep) {
            return .offline
        }
        if let busySlots = schedule.busy {
            for slot in busySlots {
                if isInRange(hour: hour, range: slot) {
                    return .busy
                }
            }
        }
        return .online
    }

    /// Get a presence map for all given persona IDs.
    static func getPresenceMap(personaIds: [String]) -> [String: Status] {
        var map: [String: Status] = [:]
        for id in personaIds { map[id] = getStatus(for: id) }
        return map
    }

    // MARK: - Private

    private static func currentHour(in timezone: String) -> Int {
        let tz = TimeZone(identifier: timezone) ?? .current
        let cal = Calendar.current
        let now = Date()
        let components = cal.dateComponents(in: tz, from: now)
        return components.hour ?? Calendar.current.component(.hour, from: now)
    }

    private static func isInRange(hour: Int, range: TimeRange) -> Bool {
        if range.start <= range.end {
            return hour >= range.start && hour < range.end
        } else {
            // Overnight: e.g. 23–7 means 23,0,1,2,3,4,5,6
            return hour >= range.start || hour < range.end
        }
    }
}
