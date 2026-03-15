import Foundation

@Observable final class SocialService {
    private(set) var points: Int = 0
    private(set) var achievementRecords: [AchievementRecord] = []
    private(set) var checkInDates: [String] = []   // "yyyy-MM-dd" strings
    private(set) var streakDays: Int = 0
    private(set) var dailyTaskState: DailyTaskState = .empty
    private(set) var giftsSentCount: Int = 0

    init() { load() }

    // MARK: - Points

    func addPoints(_ n: Int) {
        points += n
        save()
    }

    /// Returns true if the user had enough points (and deducts them).
    @discardableResult
    func spendPoints(_ n: Int) -> Bool {
        guard points >= n else { return false }
        points -= n
        save()
        return true
    }

    // MARK: - Daily Check-in

    var canCheckInToday: Bool {
        !checkInDates.contains(DailyTaskState.todayString)
    }

    /// Performs the daily check-in. Returns points earned (0 if already checked in).
    @discardableResult
    func checkIn() -> Int {
        guard canCheckInToday else { return 0 }

        checkInDates.append(DailyTaskState.todayString)
        streakDays = calculateStreak()

        let bonus = min(streakDays * 2, 20)
        let earned = 10 + bonus
        points += earned

        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 { unlockAchievement("early_bird") }
        if streakDays >= 7  { unlockAchievement("streak_7") }
        if streakDays >= 30 { unlockAchievement("streak_30") }

        updateTaskProgress("task_checkin")
        save()
        return earned
    }

    // MARK: - Achievements

    func isUnlocked(_ id: String) -> Bool {
        achievementRecords.contains { $0.id == id }
    }

    @discardableResult
    func unlockAchievement(_ id: String) -> Bool {
        guard !isUnlocked(id), let def = AchievementDefinition.def(id: id) else { return false }
        achievementRecords.append(AchievementRecord(id: id, unlockedAt: Date()))
        points += def.points
        save()
        return true
    }

    // MARK: - Daily Tasks

    func updateTaskProgress(_ taskId: String, increment: Int = 1) {
        ensureTodayState()
        guard !dailyTaskState.completed.contains(taskId),
              let def = DailyTaskDefinition.def(id: taskId) else { return }

        let current = (dailyTaskState.progress[taskId] ?? 0) + increment
        dailyTaskState.progress[taskId] = current

        if current >= def.target {
            dailyTaskState.completed.append(taskId)
            if def.points > 0 { points += def.points }
        }
        save()
    }

    func taskProgress(id: String) -> (current: Int, total: Int, completed: Bool) {
        let def = DailyTaskDefinition.def(id: id)
        let total = def?.target ?? 1
        guard dailyTaskState.isToday else { return (0, total, false) }
        let current = dailyTaskState.progress[id] ?? 0
        let done = dailyTaskState.completed.contains(id)
        return (current, total, done)
    }

    var todayCompletedCount: Int {
        guard dailyTaskState.isToday else { return 0 }
        return dailyTaskState.completed.count
    }

    // MARK: - External Event Hooks

    /// Call after every user message is sent.
    func onMessageSent(personaId: String, chatStore: ChatStore) {
        ensureTodayState()

        // task_messages (+1 per message)
        updateTaskProgress("task_messages")

        // task_chat3 (unique personas today)
        if !dailyTaskState.chatPersonasToday.contains(personaId) {
            dailyTaskState.chatPersonasToday.append(personaId)
            let count = dailyTaskState.chatPersonasToday.count
            if !dailyTaskState.completed.contains("task_chat3") {
                dailyTaskState.progress["task_chat3"] = count
                if count >= 3 {
                    dailyTaskState.completed.append("task_chat3")
                    if let def = DailyTaskDefinition.def(id: "task_chat3"), def.points > 0 {
                        points += def.points
                    }
                }
            }
        }

        // Achievements
        unlockAchievement("first_chat")

        let totalMsgs = chatStore.sessions.reduce(0) { $0 + $1.displayMessages.count }
        if totalMsgs >= 100 { unlockAchievement("chat_master") }

        let uniquePersonas = Set(chatStore.sessions.flatMap { $0.personaIds })
        if uniquePersonas.count >= 5 { unlockAchievement("social_butterfly") }

        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 4 { unlockAchievement("night_owl") }

        save()
    }

    /// Call after a gift is sent.
    func onGiftSent(intimacyAfter: Int) {
        giftsSentCount += 1
        updateTaskProgress("task_gift")
        if giftsSentCount >= 10 { unlockAchievement("gift_giver") }
        if intimacyAfter >= 100 { unlockAchievement("best_friend") }
        save()
    }

    /// Call after a game finishes (win or lose).
    func onGamePlayed() {
        updateTaskProgress("task_game")
    }

    /// Call after the user likes a Moment post.
    func onMomentLiked() {
        updateTaskProgress("task_like")
    }

    /// Call with the user's total Moment post count.
    func onMomentsPosted(total: Int) {
        if total >= 10 { unlockAchievement("moment_star") }
    }

    /// Call when any persona's intimacy reaches max.
    func onIntimacyMaxed() {
        unlockAchievement("best_friend")
    }

    // MARK: - Helpers

    private func ensureTodayState() {
        if !dailyTaskState.isToday {
            dailyTaskState = DailyTaskState(
                date: DailyTaskState.todayString,
                completed: [], progress: [:], chatPersonasToday: []
            )
        }
    }

    private func calculateStreak() -> Int {
        let sorted = checkInDates.sorted(by: >)
        guard !sorted.isEmpty else { return 0 }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var streak = 1
        for i in 1..<sorted.count {
            guard let d1 = fmt.date(from: sorted[i - 1]),
                  let d2 = fmt.date(from: sorted[i]) else { break }
            let diff = Calendar.current.dateComponents([.day], from: d2, to: d1).day ?? 0
            if diff == 1 { streak += 1 } else { break }
        }
        return streak
    }

    // MARK: - Persistence

    private struct StorageData: Codable {
        var points: Int
        var achievementRecords: [AchievementRecord]
        var checkInDates: [String]
        var streakDays: Int
        var dailyTaskState: DailyTaskState
        var giftsSentCount: Int
    }

    private func save() {
        StorageService.shared.set("social", value: StorageData(
            points: points,
            achievementRecords: achievementRecords,
            checkInDates: checkInDates,
            streakDays: streakDays,
            dailyTaskState: dailyTaskState,
            giftsSentCount: giftsSentCount
        ))
    }

    private func load() {
        guard let d: StorageData = StorageService.shared.get("social") else { return }
        points = d.points
        achievementRecords = d.achievementRecords
        checkInDates = d.checkInDates
        streakDays = d.streakDays
        dailyTaskState = d.dailyTaskState
        giftsSentCount = d.giftsSentCount
    }
}
