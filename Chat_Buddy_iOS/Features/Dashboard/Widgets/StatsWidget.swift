import SwiftUI

struct StatsWidget: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(ChatStore.self) private var chatStore

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Total visible messages across all sessions (user + AI, excludes system prompts).
    private var totalMessages: Int {
        chatStore.sessions.reduce(0) { $0 + $1.displayMessages.count }
    }

    /// Number of sessions that have at least one message.
    private var totalChats: Int {
        chatStore.sessions.filter { !$0.displayMessages.isEmpty }.count
    }

    /// Consecutive calendar days (ending today) on which at least one message was sent.
    private var streakDays: Int {
        let calendar = Calendar.current
        let fmt = Self.dayFormatter

        var activeDays = Set<String>()
        for session in chatStore.sessions where !session.displayMessages.isEmpty {
            activeDays.insert(fmt.string(from: session.updatedAt))
        }

        var streak = 0
        var date = Date()
        while activeDays.contains(fmt.string(from: date)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return streak
    }

    var body: some View {
        BentoCardView(
            icon: "chart.bar.fill",
            title: localization.t("stats"),
            iconColor: .green
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                statRow(localization.t("messages_stat"), value: "\(totalMessages)")
                statRow(localization.t("chats_stat"),    value: "\(totalChats)")
                statRow(localization.t("streak_stat"),   value: "\(streakDays) \(localization.t("days_unit"))")
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DSTypography.caption1)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(DSTypography.caption1)
                .fontWeight(.semibold)
        }
    }
}
