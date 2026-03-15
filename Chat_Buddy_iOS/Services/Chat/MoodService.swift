import Foundation

/// Time-based mood computation for AI personas.
///
/// Maps the current hour of day + a persona-specific hash to one of five
/// emotional states. The same persona always resolves to the same mood within
/// a given hour, giving the system a deterministic yet varied feel.
enum MoodService {

    // MARK: - Mood

    enum Mood: String, CaseIterable {
        case happy
        case calm
        case excited
        case tired
        case melancholy

        var emoji: String {
            switch self {
            case .happy:      return "😊"
            case .calm:       return "😌"
            case .excited:    return "🤩"
            case .tired:      return "😴"
            case .melancholy: return "😔"
            }
        }

        func localizedLabel(isZh: Bool) -> String {
            if isZh {
                switch self {
                case .happy:      return "开心"
                case .calm:       return "平静"
                case .excited:    return "兴奋"
                case .tired:      return "疲惫"
                case .melancholy: return "感慨"
                }
            } else {
                switch self {
                case .happy:      return "Happy"
                case .calm:       return "Calm"
                case .excited:    return "Excited"
                case .tired:      return "Tired"
                case .melancholy: return "Thoughtful"
                }
            }
        }

        /// Injected into the AI system prompt to shape tone and verbosity.
        var promptHint: String {
            switch self {
            case .happy:      return "You're feeling happy and upbeat! Be enthusiastic and positive."
            case .calm:       return "You're feeling calm and peaceful. Be thoughtful and relaxed."
            case .excited:    return "You're really excited right now! Use exclamation marks and be very energetic!"
            case .tired:      return "You're a bit tired. Keep responses a little shorter."
            case .melancholy: return "You're feeling thoughtful and a little introspective. Be gentle and sincere."
            }
        }

        var promptHintZh: String {
            switch self {
            case .happy:      return "你现在心情很好！保持热情积极。"
            case .calm:       return "你感到平静祥和，思维清晰。"
            case .excited:    return "你现在非常兴奋！多用感叹号，充满活力！"
            case .tired:      return "你有点累了，回复可以简短一些。"
            case .melancholy: return "你感到若有所思，内心有些感慨。保持温柔真诚。"
            }
        }
    }

    // MARK: - Public API

    /// Returns the current mood for a persona, stable within the same hour.
    /// Different personas resolve to different moods even at the same time.
    static func currentMood(for persona: Persona) -> Mood {
        let hour = Calendar.current.component(.hour, from: Date())
        let candidates = timeCandidates(for: hour)
        // XOR with hour so the mood shifts when the hour changes
        let hash = abs(persona.id.hashValue ^ hour)
        return candidates[hash % candidates.count]
    }

    // MARK: - Private

    private static func timeCandidates(for hour: Int) -> [Mood] {
        switch hour {
        case 6..<12:  // Morning
            return [.calm, .happy, .excited, .calm, .happy]
        case 12..<18: // Afternoon
            return [.happy, .excited, .happy, .calm, .excited]
        case 18..<23: // Evening
            return [.calm, .happy, .melancholy, .calm, .happy]
        default:      // Late night (23–5)
            return [.tired, .melancholy, .tired, .calm, .tired]
        }
    }
}
