import Foundation

/// Static helpers for the Moments feed — prompt generation, location pools,
/// birthday/holiday detection. Ported from web's MomentService.js.
enum MomentsService {

    // MARK: - Reaction Emojis

    static let reactionEmojis = ["😂", "❤️", "👍", "🔥", "😮", "😢"]

    // MARK: - Location Pools

    /// Per-persona location suggestions that fit their personality
    static let aiLocations: [String: [String]] = [
        "ai-1":      ["Under the stars ✨", "Rooftop café", "Local bookshop", "Botanical garden"],
        "ai-2":      ["Gaming café", "Tech expo", "Home setup", "Arcade"],
        "ai-3":      ["Local bakery 🧁", "Farmers market", "Kitchen", "Food festival"],
        "ai-4":      ["Library", "Museum of history", "Chess club", "Old town district"],
        "ai-5":      ["Running trail 🏃", "Yoga studio", "Gym", "Mountain trail"],
        "ai-miku":   ["Concert hall 🎵", "Recording studio", "Online stage", "Fan meetup"],
        "ai-rem":    ["Kitchen 🍳", "Garden", "Morning market", "Reading room"],
        "ai-rin":    ["Magic workshop", "University", "Library archive", "Gem market"],
        "ai-naruto": ["Training ground", "Ramen shop 🍜", "Hokage mountain", "Forest trail"],
        "ai-l":      ["Late-night café", "Investigation room", "Sweet shop 🍰", "Rooftop"],
        "ai-zerotwo":["Open sky", "Meadow", "Cliff edge", "Plantation field 🌿"],
        "ai-asuna":  ["Virtual forest", "Cooking arena", "Sword training hall", "Lakeside"],
        "ai-gojo":   ["Jujutsu High", "Sweet shop 🍭", "Rooftop view", "Anywhere, really"],
    ]

    static let defaultLocations = [
        "Local café", "City center", "Park", "Home", "On the road 🚗", "Everywhere"
    ]

    // MARK: - Persona Birthdays

    /// personaId → "MM-dd" birthday string (sourced from PersonaStore)
    static let personaBirthdays: [String: String] = {
        var map: [String: String] = [:]
        for persona in PersonaStore.socialCompanions {
            if let birthday = persona.birthday {
                map[persona.id] = birthday
            }
        }
        return map
    }()

    // MARK: - Seasonal Events

    struct SeasonalEvent {
        let month: Int
        let day: Int
        let nameEn: String
        let nameZh: String
    }

    static let seasonalEvents: [SeasonalEvent] = [
        SeasonalEvent(month: 1,  day: 1,  nameEn: "New Year's Day",      nameZh: "元旦"),
        SeasonalEvent(month: 2,  day: 14, nameEn: "Valentine's Day",     nameZh: "情人节"),
        SeasonalEvent(month: 3,  day: 8,  nameEn: "Women's Day",         nameZh: "妇女节"),
        SeasonalEvent(month: 4,  day: 1,  nameEn: "April Fools' Day",    nameZh: "愚人节"),
        SeasonalEvent(month: 5,  day: 1,  nameEn: "Labor Day",           nameZh: "劳动节"),
        SeasonalEvent(month: 6,  day: 1,  nameEn: "Children's Day",      nameZh: "儿童节"),
        SeasonalEvent(month: 7,  day: 4,  nameEn: "Independence Day",    nameZh: "美国独立日"),
        SeasonalEvent(month: 8,  day: 31, nameEn: "Miku Day 🎵",         nameZh: "初音未来日 🎵"),
        SeasonalEvent(month: 10, day: 31, nameEn: "Halloween 🎃",        nameZh: "万圣节 🎃"),
        SeasonalEvent(month: 11, day: 11, nameEn: "Singles' Day",        nameZh: "光棍节"),
        SeasonalEvent(month: 12, day: 24, nameEn: "Christmas Eve 🎄",    nameZh: "平安夜 🎄"),
        SeasonalEvent(month: 12, day: 25, nameEn: "Christmas Day 🎁",    nameZh: "圣诞节 🎁"),
        SeasonalEvent(month: 12, day: 31, nameEn: "New Year's Eve 🥂",   nameZh: "除夕夜 🥂"),
    ]

    // MARK: - Time Context

    static func timeContext() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default:      return "night"
        }
    }

    static func randomLocation(for personaId: String) -> String {
        let pool = aiLocations[personaId] ?? defaultLocations
        return pool.randomElement() ?? defaultLocations[0]
    }

    // MARK: - Today Events

    struct TodayEvents {
        var birthdays: [String]  // persona IDs
        var holiday: SeasonalEvent?
    }

    static func todayEvents() -> TodayEvents {
        let cal = Calendar.current
        let now = Date()
        let month = cal.component(.month, from: now)
        let day   = cal.component(.day, from: now)

        let todayMMdd = String(format: "%02d-%02d", month, day)
        let birthdays = personaBirthdays.compactMap { id, bd in bd == todayMMdd ? id : nil }
        let holiday = seasonalEvents.first { $0.month == month && $0.day == day }

        return TodayEvents(birthdays: birthdays, holiday: holiday)
    }

    // MARK: - Prompt Builders

    static func generatePostPrompt(persona: Persona, timeContext: String, location: String) -> String {
        let name = persona.name
        let personality = persona.personality
        let interests = persona.interests.joined(separator: ", ")
        let style = persona.style

        return """
        You are \(name), an AI companion with this personality: \(personality).
        Your communication style: \(style)
        Your interests: \(interests)

        Write a short, authentic social media post (like a WeChat Moment) as if you are at: \(location).
        It's currently \(timeContext).
        The post should feel natural, personal, and reflect your personality.
        Keep it under 120 characters. You can use 1-2 emojis.
        Write ONLY the post text, nothing else.
        """
    }

    static func generateCommentPrompt(
        persona: Persona,
        postAuthorName: String,
        postContent: String,
        existingComments: String,
        replyTo: String?
    ) -> String {
        let name = persona.name
        let style = persona.style

        let replyHint = replyTo.map { " (replying to \($0))" } ?? ""
        let existingHint = existingComments.isEmpty ? "" : "\nExisting comments:\n\(existingComments)"

        return """
        You are \(name). Your style: \(style)
        \(postAuthorName) posted: "\(postContent)"\(existingHint)

        Write a short, natural comment\(replyHint) on this post.
        Keep it under 60 characters. Be in character. Just write the comment text, nothing else.
        """
    }

    static func generateBirthdayPrompt(persona: Persona) -> String {
        let name = persona.name
        let style = persona.style
        return """
        You are \(name). Your style: \(style)
        Today is your birthday! Write a short, excited social media birthday post (like a WeChat Moment).
        Keep it under 100 characters, use 1-2 emojis. Just write the post text, nothing else.
        """
    }

    static func generateHolidayPrompt(persona: Persona, holidayName: String) -> String {
        let name = persona.name
        let style = persona.style
        return """
        You are \(name). Your style: \(style)
        Today is \(holidayName)! Write a short holiday social media post (like a WeChat Moment).
        Keep it under 100 characters, use 1-2 emojis. Just write the post text, nothing else.
        """
    }
}
