import SwiftUI

struct LearningReportView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(ChatStore.self) private var chatStore
    @Environment(SocialService.self) private var social

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var totalSessions: Int { chatStore.sessions.count }

    private var totalMessages: Int {
        chatStore.sessions.reduce(0) { $0 + $1.displayMessages.count }
    }

    private var topPersonas: [(name: String, count: Int)] {
        let all = chatStore.sessions.flatMap { session in
            session.personaIds.map { id in
                PersonaStore.persona(byId: id)?.localizedName(language: localization.uiLanguage) ?? id
            }
        }
        let grouped = Dictionary(grouping: all, by: { $0 }).mapValues { $0.count }
        return grouped.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private var completionRate: Double {
        guard !DailyTaskDefinition.all.isEmpty else { return 0 }
        return Double(social.todayCompletedCount) / Double(DailyTaskDefinition.all.count)
    }

    private var reportText: String {
        [
            isZh ? "学习报告" : "Learning Report",
            DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short),
            "",
            (isZh ? "会话数" : "Sessions") + ": \(totalSessions)",
            (isZh ? "消息数" : "Messages") + ": \(totalMessages)",
            (isZh ? "积分" : "Points") + ": \(social.points)",
            (isZh ? "签到连续" : "Streak") + ": \(social.streakDays)",
            (isZh ? "今日任务完成率" : "Daily Task Completion") + ": \(Int(completionRate * 100))%",
            "",
            isZh ? "高频互动角色：" : "Most interacted personas:",
            topPersonas.prefix(5).map { "- \($0.name): \($0.count)" }.joined(separator: "\n")
        ]
        .joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                metricRow(title: isZh ? "会话总数" : "Total Sessions", value: "\(totalSessions)")
                metricRow(title: isZh ? "消息总数" : "Total Messages", value: "\(totalMessages)")
                metricRow(title: isZh ? "累计积分" : "Total Points", value: "\(social.points)")
                metricRow(title: isZh ? "连续签到" : "Check-in Streak", value: "\(social.streakDays)")
                metricRow(title: isZh ? "今日任务完成" : "Task Completion Today", value: "\(Int(completionRate * 100))%")
            }

            Section(isZh ? "高频互动角色" : "Top Personas") {
                if topPersonas.isEmpty {
                    Text(isZh ? "暂无数据" : "No data yet")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(topPersonas.prefix(8).enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text("#\(index + 1)")
                                .font(DSTypography.caption1.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .leading)
                            Text(item.name)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                ShareLink(item: reportText) {
                    Label(isZh ? "导出报告" : "Export Report", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(isZh ? "学习报告" : "Learning Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
