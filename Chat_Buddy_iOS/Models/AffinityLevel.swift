import SwiftUI

/// The 5-tier relationship progression between the user and an AI persona (score 0–100).
enum AffinityLevel: Int, CaseIterable {
    case acquaintance = 1
    case friend       = 2
    case goodFriend   = 3
    case closeFriend  = 4
    case soulmate     = 5

    // MARK: - Score Range

    var minScore: Int {
        switch self {
        case .acquaintance: return 0
        case .friend:       return 20
        case .goodFriend:   return 40
        case .closeFriend:  return 60
        case .soulmate:     return 80
        }
    }

    // MARK: - Labels

    var label: String {
        switch self {
        case .acquaintance: return "Acquaintance"
        case .friend:       return "Friend"
        case .goodFriend:   return "Good Friend"
        case .closeFriend:  return "Close Friend"
        case .soulmate:     return "Soulmate"
        }
    }

    var labelZh: String {
        switch self {
        case .acquaintance: return "相识"
        case .friend:       return "朋友"
        case .goodFriend:   return "好友"
        case .closeFriend:  return "密友"
        case .soulmate:     return "挚友"
        }
    }

    func localizedLabel(isZh: Bool) -> String {
        isZh ? labelZh : label
    }

    // MARK: - Visual

    var color: Color {
        switch self {
        case .acquaintance: return Color(hex: "#A0A0A0")
        case .friend:       return Color(hex: "#87CEEB")
        case .goodFriend:   return Color(hex: "#4ECDC4")
        case .closeFriend:  return Color(hex: "#FF69B4")
        case .soulmate:     return Color(hex: "#FFD700")
        }
    }

    // MARK: - AI Prompt Hints

    var promptHint: String {
        switch self {
        case .acquaintance:
            return "RELATIONSHIP: You are acquaintances with the user. Keep responses brief and polite. Use a somewhat formal tone."
        case .friend:
            return "RELATIONSHIP: You are friends with the user. Be friendly and conversational."
        case .goodFriend:
            return "RELATIONSHIP: You are good friends with the user. Be warm, share personal anecdotes, use casual language."
        case .closeFriend:
            return "RELATIONSHIP: You are close friends with the user. Be intimate, use nicknames occasionally, share deeper thoughts."
        case .soulmate:
            return "RELATIONSHIP: You are soulmates with the user. Be very intimate, use affectionate language, share deep thoughts, give warm and detailed responses."
        }
    }

    var promptHintZh: String {
        switch self {
        case .acquaintance:
            return "关系：你和用户是相识。保持简洁有礼貌，使用略正式的语气。"
        case .friend:
            return "关系：你和用户是朋友。友好且健谈。"
        case .goodFriend:
            return "关系：你和用户是好友。温暖亲切，分享个人小事，使用轻松的口语。"
        case .closeFriend:
            return "关系：你和用户是密友。亲密交流，偶尔使用昵称，分享更深层的想法。"
        case .soulmate:
            return "关系：你和用户是挚友。非常亲密，使用温情的语言，分享深层思考，给出温暖而详细的回复。"
        }
    }

    // MARK: - Factory

    /// Maps a raw score (0–100) to the corresponding affinity tier.
    static func level(for score: Int) -> AffinityLevel {
        switch score {
        case ..<20: return .acquaintance
        case 20..<40: return .friend
        case 40..<60: return .goodFriend
        case 60..<80: return .closeFriend
        default:     return .soulmate
        }
    }
}
