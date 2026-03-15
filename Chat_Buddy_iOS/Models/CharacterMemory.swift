import SwiftUI

// MARK: - Memory Category

enum MemoryCategory: String, Codable, CaseIterable {
    case preference, fact, event

    var label: String {
        switch self {
        case .preference: return "Preference"
        case .fact:       return "Fact"
        case .event:      return "Event"
        }
    }

    var labelZh: String {
        switch self {
        case .preference: return "偏好"
        case .fact:       return "事实"
        case .event:      return "事件"
        }
    }

    var color: Color {
        switch self {
        case .preference: return .blue
        case .fact:       return .green
        case .event:      return .purple
        }
    }

    /// Returns an emoji indicator based on importance level (1–10).
    func importanceLabel(_ n: Int) -> String {
        switch n {
        case 1...2: return "⬜"
        case 3...4: return "🟨"
        case 5...6: return "🟧"
        case 7...8: return "🟥"
        default:    return "⭐"
        }
    }
}

// MARK: - Character Memory

struct CharacterMemory: Identifiable, Codable {
    var id: String = UUID().uuidString
    var personaId: String
    var fact: String
    var category: MemoryCategory
    var importance: Int          // 1–10
    var createdAt: Date
    var lastRecalledAt: Date
    var isForgotten: Bool = false
}

// MARK: - Persistence Wrapper

struct MemoriesData: Codable {
    var memoriesByPersona: [String: [CharacterMemory]]
}
