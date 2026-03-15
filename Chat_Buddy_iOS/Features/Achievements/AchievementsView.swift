import SwiftUI

struct AchievementsView: View {
    @Environment(SocialService.self) private var social
    @Environment(LocalizationManager.self) private var localization
    @State private var selectedCategory: AchievementCategory? = nil
    @State private var showCheckIn = false

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var filtered: [AchievementDefinition] {
        guard let cat = selectedCategory else { return AchievementDefinition.all }
        return AchievementDefinition.all.filter { $0.category == cat }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    statsHeader
                    categoryFilter
                    achievementGrid
                    dailyTasksSection
                }
                .padding(DSSpacing.md)
                .padding(.bottom, DSSpacing.huge)
            }
            .navigationTitle(localization.t("achievements_title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCheckIn = true
                    } label: {
                        Image(systemName: "calendar.badge.checkmark")
                    }
                }
            }
            .sheet(isPresented: $showCheckIn) {
                DailyCheckInView()
            }
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 0) {
            statCell(
                value: "\(social.achievementRecords.count)/\(AchievementDefinition.all.count)",
                label: isZh ? "已解锁" : "Unlocked",
                icon: "trophy.fill",
                color: .yellow
            )
            Divider().frame(height: 50)
            statCell(
                value: "\(social.points)",
                label: isZh ? "积分" : "Points",
                icon: "star.fill",
                color: .orange
            )
            Divider().frame(height: 50)
            statCell(
                value: "\(social.streakDays)",
                label: isZh ? "连续天" : "Streak",
                icon: "flame.fill",
                color: .red
            )
        }
        .padding(DSSpacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.xl))
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(DSTypography.title3).fontWeight(.bold)
            Text(label).font(DSTypography.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                filterPill(label: isZh ? "全部" : "All", category: nil)
                ForEach(AchievementCategory.allCases, id: \.self) { cat in
                    filterPill(label: isZh ? cat.labelZh : cat.label, category: cat)
                }
            }
            .padding(.horizontal, DSSpacing.xs)
        }
    }

    private func filterPill(label: String, category: AchievementCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.spring(response: 0.3)) { selectedCategory = category }
        } label: {
            Text(label)
                .font(DSTypography.footnote.weight(.medium))
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.xs)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Achievement Grid

    private var achievementGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: DSSpacing.sm) {
            ForEach(filtered) { def in
                achievementCard(def)
            }
        }
    }

    private func achievementCard(_ def: AchievementDefinition) -> some View {
        let unlocked = social.isUnlocked(def.id)
        let record   = social.achievementRecords.first { $0.id == def.id }

        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Image(systemName: def.icon)
                    .font(.title2)
                    .foregroundStyle(unlocked ? .yellow : .secondary)
                Spacer()
                Text("+\(def.points)")
                    .font(DSTypography.caption2)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(unlocked ? 0.15 : 0.07), in: Capsule())
                    .foregroundStyle(unlocked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }

            Text(isZh ? def.nameZh : def.name)
                .font(DSTypography.footnote.weight(.semibold))
                .foregroundStyle(unlocked ? .primary : .secondary)

            Text(isZh ? def.descriptionZh : def.description)
                .font(DSTypography.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            if let record {
                Text(record.unlockedAt, style: .date)
                    .font(DSTypography.caption2)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .regularMaterial.opacity(unlocked ? 1 : 0.5),
            in: RoundedRectangle(cornerRadius: DSRadius.lg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .strokeBorder(unlocked ? Color.yellow.opacity(0.3) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .grayscale(unlocked ? 0 : 0.7)
    }

    // MARK: - Daily Tasks

    private var dailyTasksSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(isZh ? "今日任务" : "Daily Tasks")
                    .font(DSTypography.headline)
                Spacer()
                Text("\(social.todayCompletedCount)/\(DailyTaskDefinition.all.count)")
                    .font(DSTypography.caption1)
                    .foregroundStyle(.secondary)
                Button {
                    showCheckIn = true
                } label: {
                    Text(localization.t("checkin_button"))
                        .font(DSTypography.caption1)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }

            VStack(spacing: 0) {
                ForEach(DailyTaskDefinition.all) { task in
                    taskRow(task)
                    if task.id != DailyTaskDefinition.all.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))
        }
    }

    private func taskRow(_ task: DailyTaskDefinition) -> some View {
        let prog = social.taskProgress(id: task.id)
        return HStack(spacing: DSSpacing.sm) {
            Image(systemName: prog.completed ? "checkmark.circle.fill" : task.icon)
                .foregroundStyle(prog.completed ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(isZh ? task.nameZh : task.name)
                    .font(DSTypography.footnote)
                    .foregroundStyle(prog.completed ? .secondary : .primary)
                if !prog.completed {
                    ProgressView(value: Double(prog.current), total: Double(prog.total))
                        .tint(.accentColor)
                        .frame(maxWidth: 120)
                }
            }
            Spacer()
            if task.points > 0 {
                Text(prog.completed ? "✓" : "+\(task.points)")
                    .font(DSTypography.caption2)
                    .foregroundStyle(prog.completed ? AnyShapeStyle(.green) : AnyShapeStyle(Color.accentColor))
            }
        }
        .padding(DSSpacing.sm)
        .opacity(prog.completed ? 0.6 : 1)
    }
}
