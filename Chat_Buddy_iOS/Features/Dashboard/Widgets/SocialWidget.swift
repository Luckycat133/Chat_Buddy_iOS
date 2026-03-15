import SwiftUI

struct SocialWidget: View {
    @Environment(SocialService.self) private var social
    @Environment(LocalizationManager.self) private var localization
    @State private var showCheckIn = false
    @State private var showAchievements = false

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    var body: some View {
        GlassCard {
            HStack(spacing: DSSpacing.md) {
                // Points + streak
                HStack(spacing: DSSpacing.lg) {
                    statPill(
                        icon: "star.fill",
                        color: .yellow,
                        value: "\(social.points)",
                        label: isZh ? "积分" : "Pts"
                    )
                    Divider().frame(height: 36)
                    statPill(
                        icon: "flame.fill",
                        color: .orange,
                        value: "\(social.streakDays)",
                        label: isZh ? "连续" : "Streak"
                    )
                    Divider().frame(height: 36)
                    statPill(
                        icon: "trophy.fill",
                        color: .purple,
                        value: "\(social.achievementRecords.count)",
                        label: isZh ? "成就" : "Awards"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Action buttons
                VStack(spacing: DSSpacing.xs) {
                    Button {
                        showCheckIn = true
                    } label: {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: social.canCheckInToday ? "checkmark.seal" : "checkmark.seal.fill")
                                .font(.caption)
                            Text(isZh ? "签到" : "Check In")
                                .font(DSTypography.caption2.weight(.medium))
                        }
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            social.canCheckInToday ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(social.canCheckInToday ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!social.canCheckInToday)

                    Button {
                        showAchievements = true
                    } label: {
                        Text(isZh ? "成就" : "Achievements")
                            .font(DSTypography.caption2.weight(.medium))
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showCheckIn) { DailyCheckInView() }
        .sheet(isPresented: $showAchievements) { AchievementsView() }
    }

    private func statPill(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DSTypography.caption2)
                    .foregroundStyle(color)
                Text(value)
                    .font(DSTypography.subheadline.weight(.bold))
            }
            Text(label)
                .font(DSTypography.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
