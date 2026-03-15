import SwiftUI

struct DailyCheckInView: View {
    @Environment(SocialService.self) private var social
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    @State private var justCheckedIn = false
    @State private var earnedPoints = 0

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.xl) {
                // Header card
                streakHeader

                // Week calendar
                weekCalendar

                // Tasks preview
                tasksSummary

                Spacer()

                // Check-in button
                checkInButton
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.xl)
            .navigationTitle(localization.t("checkin_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.t("done")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Streak Header

    private var streakHeader: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xl) {
                statItem(value: "\(social.streakDays)", label: isZh ? "连续天数" : "Day Streak", icon: "flame.fill", color: .orange)
                Divider().frame(height: 40)
                statItem(value: "\(social.points)", label: isZh ? "总积分" : "Total Points", icon: "star.fill", color: .yellow)
                Divider().frame(height: 40)
                statItem(value: "\(social.achievementRecords.count)", label: isZh ? "成就" : "Achievements", icon: "trophy.fill", color: .purple)
            }
        }
        .padding(DSSpacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.xl))
        .padding(.top, DSSpacing.sm)
    }

    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(value)
                .font(DSTypography.title2)
                .fontWeight(.bold)
            Text(label)
                .font(DSTypography.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Week Calendar

    private var weekCalendar: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(isZh ? "本周签到" : "This Week")
                .font(DSTypography.headline)

            HStack(spacing: DSSpacing.xs) {
                ForEach(last7Days(), id: \.self) { dateStr in
                    dayCell(dateStr: dateStr)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayCell(dateStr: String) -> some View {
        let isChecked = social.checkInDates.contains(dateStr)
        let isToday   = dateStr == DailyTaskState.todayString
        let weekday   = weekdayLabel(dateStr)

        return VStack(spacing: DSSpacing.xxs) {
            Text(weekday)
                .font(DSTypography.caption2)
                .foregroundStyle(.secondary)
            Circle()
                .fill(isChecked ? Color.accentColor : Color.secondary.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay(
                    Group {
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                )
                .overlay(
                    Circle()
                        .strokeBorder(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tasks Summary

    private var tasksSummary: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(isZh ? "今日任务" : "Daily Tasks")
                    .font(DSTypography.headline)
                Spacer()
                Text("\(social.todayCompletedCount)/\(DailyTaskDefinition.all.count)")
                    .font(DSTypography.caption1)
                    .foregroundStyle(.secondary)
            }

            ForEach(DailyTaskDefinition.all) { task in
                let prog = social.taskProgress(id: task.id)
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: prog.completed ? "checkmark.circle.fill" : task.icon)
                        .foregroundStyle(prog.completed ? .green : .secondary)
                        .frame(width: 20)
                    Text(isZh ? task.nameZh : task.name)
                        .font(DSTypography.footnote)
                    Spacer()
                    if task.points > 0 {
                        Text("+\(task.points)")
                            .font(DSTypography.caption2)
                            .foregroundStyle(prog.completed ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    }
                    Text("\(prog.current)/\(prog.total)")
                        .font(DSTypography.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, DSSpacing.xxs)
                .opacity(prog.completed ? 0.6 : 1.0)
            }
        }
        .padding(DSSpacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.xl))
    }

    // MARK: - Check-in Button

    private var checkInButton: some View {
        Group {
            if justCheckedIn {
                VStack(spacing: DSSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text(isZh ? "签到成功！+\(earnedPoints)积分 🎉" : "Checked in! +\(earnedPoints) pts 🎉")
                        .font(DSTypography.headline)
                }
                .transition(.scale.combined(with: .opacity))
            } else if social.canCheckInToday {
                Button {
                    let pts = social.checkIn()
                    withAnimation(.spring) {
                        earnedPoints = pts
                        justCheckedIn = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text(localization.t("checkin_button"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DSSpacing.md)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: DSRadius.xl))
                    .foregroundStyle(.white)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text(localization.t("checkin_done"))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(DSSpacing.md)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.xl))
            }
        }
    }

    // MARK: - Helpers

    private func last7Days() -> [String] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return (0..<7).reversed().compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date()).map { fmt.string(from: $0) }
        }
    }

    private func weekdayLabel(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return "" }
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE"
        dayFmt.locale = Locale(identifier: isZh ? "zh_CN" : "en_US")
        return dayFmt.string(from: date)
    }
}
