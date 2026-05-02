import SwiftUI

enum AgentType: String, Codable {
    case socialCompanion = "social-companion"
    case taskSpecialist = "task-specialist"
}

enum AgentCategory: String, Codable {
    case productivity
    case education
    case wellbeing
    case creative
}

struct Persona: Identifiable, Codable, Equatable, Hashable {
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

    static func == (lhs: Persona, rhs: Persona) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var accentColor: Color {
        PersonaStore.colorMap[id] ?? .blue
    }

    func generateResponseDelay() -> Double {
        switch agentType {
        case .socialCompanion: return Double.random(in: 1.0...2.5)
        case .taskSpecialist:  return Double.random(in: 0.4...1.2)
        }
    }

    func localizedName(language: AppLanguage) -> String {
        language.resolved == .zh ? nameZh : name
    }

    func localizedPersonality(language: AppLanguage) -> String {
        language.resolved == .zh ? personalityZh : personality
    }

    func localizedInterests(language: AppLanguage) -> [String] {
        language.resolved == .zh ? interestsZh : interests
    }

    func localizedStyle(language: AppLanguage) -> String {
        language.resolved == .zh ? styleZh : style
    }
}
