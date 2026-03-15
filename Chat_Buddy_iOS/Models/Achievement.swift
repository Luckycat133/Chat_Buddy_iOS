import Foundation

// MARK: - Achievement Category

enum AchievementCategory: String, CaseIterable, Codable {
    case social, streak, gifts

    var label: String {
        switch self {
        case .social: return "Social"
        case .streak: return "Streak"
        case .gifts:  return "Gifts"
        }
    }
    var labelZh: String {
        switch self {
        case .social: return "社交"
        case .streak: return "连续"
        case .gifts:  return "礼物"
        }
    }
    var icon: String {
        switch self {
        case .social: return "person.2.fill"
        case .streak: return "flame.fill"
        case .gifts:  return "gift.fill"
        }
    }
}

// MARK: - Achievement Definition (static)

struct AchievementDefinition: Identifiable {
    let id: String
    let name: String
    let nameZh: String
    let description: String
    let descriptionZh: String
    let icon: String        // SF Symbol
    let points: Int
    let category: AchievementCategory

    // swiftlint:disable line_length
    static let all: [AchievementDefinition] = [
        .init(id: "first_chat",       name: "First Steps",      nameZh: "初次相识",
              description: "Send your first message",           descriptionZh: "发送第一条消息",
              icon: "message.fill",                             points: 10,  category: .social),
        .init(id: "chat_master",      name: "Chat Master",      nameZh: "对话达人",
              description: "Send 100 messages",                 descriptionZh: "发送100条消息",
              icon: "bubble.left.and.bubble.right.fill",        points: 50,  category: .social),
        .init(id: "social_butterfly", name: "Social Butterfly", nameZh: "社交达人",
              description: "Chat with 5 different characters",  descriptionZh: "与5位不同角色聊天",
              icon: "person.3.fill",                            points: 80,  category: .social),
        .init(id: "best_friend",      name: "Best Friends",     nameZh: "挚友",
              description: "Max out intimacy with someone",     descriptionZh: "与某个角色达到满亲密度",
              icon: "heart.fill",                               points: 200, category: .social),
        .init(id: "moment_star",      name: "Moment Star",      nameZh: "动态达人",
              description: "Post 10 moments",                   descriptionZh: "发布10条动态",
              icon: "sparkles",                                  points: 60,  category: .social),
        .init(id: "early_bird",       name: "Early Bird",       nameZh: "早起鸟",
              description: "Check in before 6 AM",              descriptionZh: "在早上6点前签到",
              icon: "sunrise.fill",                             points: 30,  category: .streak),
        .init(id: "night_owl",        name: "Night Owl",        nameZh: "夜猫子",
              description: "Chat after midnight",               descriptionZh: "在午夜后聊天",
              icon: "moon.stars.fill",                          points: 30,  category: .streak),
        .init(id: "streak_7",         name: "Dedicated",        nameZh: "坚持一周",
              description: "7-day check-in streak",             descriptionZh: "连续签到7天",
              icon: "flame.fill",                               points: 100, category: .streak),
        .init(id: "streak_30",        name: "Legendary",        nameZh: "传奇玩家",
              description: "30-day check-in streak",            descriptionZh: "连续签到30天",
              icon: "crown.fill",                               points: 500, category: .streak),
        .init(id: "gift_giver",       name: "Generous",         nameZh: "慷慨之人",
              description: "Send 10 gifts",                     descriptionZh: "赠送10份礼物",
              icon: "gift.fill",                                points: 50,  category: .gifts),
    ]
    // swiftlint:enable line_length

    static func def(id: String) -> AchievementDefinition? {
        all.first { $0.id == id }
    }
}

// MARK: - Achievement Record (persisted)

struct AchievementRecord: Codable, Identifiable {
    let id: String          // matches AchievementDefinition.id
    let unlockedAt: Date
}

// MARK: - Gift Definition

struct GiftDefinition: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let nameZh: String
    let cost: Int           // points required
    let intimacyBoost: Int  // added to affinity score

    static let all: [GiftDefinition] = [
        .init(id: "flower",   emoji: "🌹", name: "Flower",  nameZh: "玫瑰花", cost: 10,  intimacyBoost: 5),
        .init(id: "cake",     emoji: "🎂", name: "Cake",    nameZh: "蛋糕",   cost: 20,  intimacyBoost: 10),
        .init(id: "heart",    emoji: "❤️", name: "Heart",   nameZh: "爱心",   cost: 30,  intimacyBoost: 15),
        .init(id: "star",     emoji: "⭐", name: "Star",    nameZh: "星星",   cost: 50,  intimacyBoost: 20),
        .init(id: "diamond",  emoji: "💎", name: "Diamond", nameZh: "钻石",   cost: 100, intimacyBoost: 50),
        .init(id: "crown",    emoji: "👑", name: "Crown",   nameZh: "皇冠",   cost: 200, intimacyBoost: 100),
    ]
}

// MARK: - Daily Task Definition (static)

struct DailyTaskDefinition: Identifiable {
    let id: String
    let name: String
    let nameZh: String
    let icon: String        // SF Symbol
    let points: Int
    let target: Int

    static let all: [DailyTaskDefinition] = [
        .init(id: "task_checkin",  name: "Daily check-in",        nameZh: "每日签到",    icon: "checkmark.circle.fill", points: 0,  target: 1),
        .init(id: "task_messages", name: "Send 5 messages",        nameZh: "发送5条消息", icon: "message.fill",           points: 20, target: 5),
        .init(id: "task_game",     name: "Play a game",            nameZh: "玩一局游戏",  icon: "gamecontroller.fill",    points: 30, target: 1),
        .init(id: "task_gift",     name: "Send a gift",            nameZh: "赠送一份礼物", icon: "gift.fill",             points: 10, target: 1),
        .init(id: "task_like",     name: "Like a moment",          nameZh: "给动态点赞",  icon: "heart.fill",             points: 15, target: 1),
        .init(id: "task_chat3",    name: "Chat with 3 characters", nameZh: "与3位角色聊天", icon: "person.3.fill",        points: 50, target: 3),
    ]

    static func def(id: String) -> DailyTaskDefinition? {
        all.first { $0.id == id }
    }
}

// MARK: - Daily Task State (persisted)

struct DailyTaskState: Codable {
    var date: String                    // "yyyy-MM-dd"
    var completed: [String]             // task IDs
    var progress: [String: Int]         // taskId → current count
    var chatPersonasToday: [String]     // persona IDs messaged today (for task_chat3)

    static let empty = DailyTaskState(date: "", completed: [], progress: [:], chatPersonasToday: [])

    var isToday: Bool { date == Self.todayString }

    static var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
