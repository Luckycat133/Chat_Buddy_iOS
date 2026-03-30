import SwiftUI

private enum LeaderboardTab: String, CaseIterable, Identifiable {
    case intimacy
    case points
    case streak
    case achievements

    var id: String { rawValue }
}

struct LeaderboardView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(SocialService.self) private var social
    @Environment(AffinityService.self) private var affinity

    @State private var selectedTab: LeaderboardTab = .intimacy

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var intimacyRanks: [(persona: Persona, score: Int, level: AffinityLevel)] {
        PersonaStore.allPersonas
            .map { persona in
                let score = affinity.score(for: persona.id)
                return (persona, score, affinity.level(for: persona.id))
            }
            .sorted { $0.score > $1.score }
    }

    private var unlockedDefinitions: [AchievementDefinition] {
        social.achievementRecords
            .compactMap { AchievementDefinition.def(id: $0.id) }
            .sorted { $0.points > $1.points }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                statsHeader
                tabSelector
                tabContent
            }
            .padding(DSSpacing.md)
            .padding(.bottom, DSSpacing.xl)
        }
        .navigationTitle(isZh ? "排行榜" : "Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statsHeader: some View {
        HStack(spacing: DSSpacing.sm) {
            statCard(icon: "star.fill", value: "\(social.points)", label: isZh ? "积分" : "Points", color: .yellow)
            statCard(icon: "flame.fill", value: "\(social.streakDays)", label: isZh ? "连续" : "Streak", color: .orange)
            statCard(icon: "trophy.fill", value: "\(social.achievementRecords.count)", label: isZh ? "成就" : "Awards", color: .purple)
        }
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(DSTypography.title3.weight(.bold))
            Text(label)
                .font(DSTypography.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))
    }

    private var tabSelector: some View {
        Picker("", selection: $selectedTab) {
            Text(isZh ? "亲密度" : "Intimacy").tag(LeaderboardTab.intimacy)
            Text(isZh ? "积分" : "Points").tag(LeaderboardTab.points)
            Text(isZh ? "签到" : "Streak").tag(LeaderboardTab.streak)
            Text(isZh ? "成就" : "Achievements").tag(LeaderboardTab.achievements)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .intimacy:
            VStack(spacing: DSSpacing.xs) {
                ForEach(Array(intimacyRanks.enumerated()), id: \.element.persona.id) { index, item in
                    HStack(spacing: DSSpacing.sm) {
                        Text(rankLabel(index))
                            .font(DSTypography.footnote.weight(.semibold))
                            .foregroundStyle(index < 3 ? Color.orange : Color.secondary)
                            .frame(width: 30, alignment: .leading)

                        Circle()
                            .fill(item.persona.accentColor.opacity(0.18))
                            .frame(width: 30, height: 30)
                            .overlay(Text(String(item.persona.name.prefix(1))).font(.caption).foregroundStyle(item.persona.accentColor))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.persona.localizedName(language: localization.uiLanguage))
                                .font(DSTypography.footnote.weight(.semibold))
                            Text(item.level.localizedLabel(isZh: isZh))
                                .font(DSTypography.caption2)
                                .foregroundStyle(item.level.color)
                        }

                        Spacer()

                        Text("\(item.score)/100")
                            .font(DSTypography.caption1.weight(.semibold))
                    }
                    .padding(DSSpacing.sm)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.md))
                }
            }

        case .points:
            summaryCard(
                icon: "star.circle.fill",
                title: isZh ? "总积分" : "Total Points",
                value: "\(social.points)",
                color: .yellow
            )

        case .streak:
            summaryCard(
                icon: "flame.circle.fill",
                title: isZh ? "连续签到" : "Current Streak",
                value: "\(social.streakDays)",
                color: .orange
            )

        case .achievements:
            if unlockedDefinitions.isEmpty {
                Text(isZh ? "暂无已解锁成就" : "No unlocked achievements")
                    .font(DSTypography.caption1)
                    .foregroundStyle(.secondary)
                    .padding(.top, DSSpacing.xl)
            } else {
                VStack(spacing: DSSpacing.xs) {
                    ForEach(unlockedDefinitions) { def in
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: def.icon)
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isZh ? def.nameZh : def.name)
                                    .font(DSTypography.footnote.weight(.semibold))
                                Text(isZh ? def.descriptionZh : def.description)
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+\(def.points)")
                                .font(DSTypography.caption1.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        .padding(DSSpacing.sm)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.md))
                    }
                }
            }
        }
    }

    private func summaryCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(color)
            Text(value)
                .font(DSTypography.largeTitle)
            Text(title)
                .font(DSTypography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.xl))
    }

    private func rankLabel(_ rank: Int) -> String {
        switch rank {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "#\(rank + 1)"
        }
    }
}
