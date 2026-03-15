import SwiftUI

/// Agent type categorization
enum AgentType: String, Codable {
    case socialCompanion = "social-companion"
    case taskSpecialist = "task-specialist"
}

/// Category for task specialists
enum AgentCategory: String, Codable {
    case productivity
    case education
    case wellbeing
    case creative
}

/// An AI persona / character definition
struct Persona: Identifiable, Codable {
    let id: String
    let name: String
    let nameZh: String
    let avatar: String
    let birthday: String?
    let personality: String
    let personalityZh: String
    let interests: [String]
    let interestsZh: [String]
    let style: String
    let styleZh: String
    let agentType: AgentType
    let category: AgentCategory?

    /// Accent color for this persona
    var accentColor: Color {
        PersonaStore.colorMap[id] ?? .blue
    }

    /// Minimum time (seconds) before an AI response is shown, for natural pacing.
    /// Social companions have a longer "thinking" window; task agents respond more briskly.
    var minimumResponseDelay: Double {
        switch agentType {
        case .socialCompanion: return Double.random(in: 1.0...2.5)
        case .taskSpecialist:  return Double.random(in: 0.4...1.2)
        }
    }

    /// Localized name
    func localizedName(language: AppLanguage) -> String {
        language.resolved == .zh ? nameZh : name
    }

    /// Localized personality
    func localizedPersonality(language: AppLanguage) -> String {
        language.resolved == .zh ? personalityZh : personality
    }

    /// Localized interests
    func localizedInterests(language: AppLanguage) -> [String] {
        language.resolved == .zh ? interestsZh : interests
    }
}
