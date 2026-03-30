import Foundation

/// Proactive greeting system — generates time-contextual greetings from personas.
/// Port of GreetingService.js.
enum GreetingService {

    // MARK: - Constants

    private static let perPersonaCooldownSeconds: TimeInterval = 12 * 3600  // 12 hours
    private static let globalCooldownSeconds: TimeInterval = 4 * 3600       // 4 hours
    private static let windowOpenThresholdSeconds: TimeInterval = 6 * 3600  // 6 hours since last msg
    private static let reEngagementThresholdSeconds: TimeInterval = 12 * 3600

    // MARK: - Greeting Templates

    struct GreetingTemplate {
        let en: String
        let zh: String
    }

    private static let morning: [GreetingTemplate] = [
        .init(en: "Good morning! ☀️ Ready for a new day?", zh: "早安！新的一天开始啦 ☀️"),
        .init(en: "Morning! How did you sleep?", zh: "早上好～昨晚睡得好吗？"),
        .init(en: "Rise and shine! 🌅", zh: "早起的鸟儿有虫吃！🌅"),
    ]

    private static let afternoon: [GreetingTemplate] = [
        .init(en: "Good afternoon~ Taking a break?", zh: "下午好～有没有好好休息一下？"),
        .init(en: "Hey! How's your day going?", zh: "嗨！今天过得怎么样？"),
        .init(en: "Afternoon! Need any help?", zh: "下午好！需要帮忙吗？"),
    ]

    private static let evening: [GreetingTemplate] = [
        .init(en: "Good evening! How was your day?", zh: "晚上好！今天过得怎么样？"),
        .init(en: "Evening~ Time to relax! 🌆", zh: "傍晚了～该放松一下了 🌆"),
        .init(en: "Hey! Ready to wind down?", zh: "嗨！准备好放松了吗？"),
    ]

    private static let lateNight: [GreetingTemplate] = [
        .init(en: "Still up? Get some rest soon! 🌙", zh: "这么晚了还没睡呀？注意休息哦 🌙"),
        .init(en: "Night owl! Don't stay up too late~", zh: "夜猫子！别熬太晚～"),
        .init(en: "Late night thoughts? I'm here if you need me.", zh: "深夜了，有什么心事吗？"),
    ]

    private static let reEngagement: [GreetingTemplate] = [
        .init(en: "Long time no see! How have you been?", zh: "好久不见！最近怎么样？"),
        .init(en: "I missed chatting with you! 🥺", zh: "好想和你聊天呀！🥺"),
        .init(en: "Hey! It's been a while~", zh: "嗨！好久没聊了～"),
    ]

    // MARK: - Cooldown State

    private struct Cooldowns: Codable {
        var perPersona: [String: Date] = [:]
        var globalLast: Date = .distantPast
    }

    private static let cooldownKey = "chat-buddy-greeting-cooldowns"

    private static func loadCooldowns() -> Cooldowns {
        StorageService.shared.get(cooldownKey, default: Cooldowns())
    }

    private static func saveCooldowns(_ c: Cooldowns) {
        StorageService.shared.set(cooldownKey, value: c)
    }

    // MARK: - Public API

    struct Greeting {
        let personaId: String
        let message: String
    }

    /// Check if a greeting should be shown when opening a chat session.
    static func checkWindowOpenGreeting(
        lastMessageDate: Date?,
        personaId: String,
        isZh: Bool
    ) -> String? {
        guard let lastMsg = lastMessageDate else { return nil }

        let elapsed = Date().timeIntervalSince(lastMsg)
        guard elapsed > windowOpenThresholdSeconds else { return nil }

        // Check persona status
        let status = PresenceService.getStatus(for: personaId)
        guard status == .online else { return nil }

        // Check cooldowns
        var cooldowns = loadCooldowns()
        let now = Date()

        if now.timeIntervalSince(cooldowns.globalLast) < globalCooldownSeconds { return nil }
        if let last = cooldowns.perPersona[personaId],
           now.timeIntervalSince(last) < perPersonaCooldownSeconds { return nil }

        // Pick template by time of day
        let hour = Calendar.current.component(.hour, from: now)
        let template = pickTemplate(hour: hour, isReEngagement: false)
        let message = isZh ? template.zh : template.en

        // Update cooldowns
        cooldowns.perPersona[personaId] = now
        cooldowns.globalLast = now
        saveCooldowns(cooldowns)

        return message
    }

    /// Check if a re-engagement greeting should show across all chats (e.g., for dashboard).
    static func checkReEngagement(
        sessions: [(personaId: String, lastMessageDate: Date?)],
        isZh: Bool
    ) -> Greeting? {
        var cooldowns = loadCooldowns()
        let now = Date()

        guard now.timeIntervalSince(cooldowns.globalLast) >= globalCooldownSeconds else { return nil }

        // Find the persona with the longest silence that is online and not on cooldown
        let candidates = sessions
            .filter { pair in
                guard let last = pair.lastMessageDate else { return false }
                let elapsed = now.timeIntervalSince(last)
                guard elapsed > reEngagementThresholdSeconds else { return false }
                let status = PresenceService.getStatus(for: pair.personaId)
                guard status == .online else { return false }
                if let cooldown = cooldowns.perPersona[pair.personaId],
                   now.timeIntervalSince(cooldown) < perPersonaCooldownSeconds { return false }
                return true
            }
            .sorted { ($0.lastMessageDate ?? .distantPast) < ($1.lastMessageDate ?? .distantPast) }

        guard let top = candidates.first else { return nil }

        let template = reEngagement.randomElement() ?? reEngagement[0]
        let message = isZh ? template.zh : template.en

        cooldowns.perPersona[top.personaId] = now
        cooldowns.globalLast = now
        saveCooldowns(cooldowns)

        return Greeting(personaId: top.personaId, message: message)
    }

    // MARK: - Private

    private static func pickTemplate(hour: Int, isReEngagement: Bool) -> GreetingTemplate {
        if isReEngagement { return reEngagement.randomElement()! }
        let templates: [GreetingTemplate]
        switch hour {
        case 6..<12:  templates = morning
        case 12..<18: templates = afternoon
        case 18..<22: templates = evening
        default:      templates = lateNight
        }
        return templates.randomElement()!
    }
}
