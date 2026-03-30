import SwiftUI

struct FriendGroupsView: View {
    @Environment(FriendService.self) private var friendService
    @Environment(LocalizationManager.self) private var localization

    @State private var draftNameEn = ""
    @State private var draftNameZh = ""
    @State private var draftIcon = "✨"
    @State private var draftColor = "#8B5CF6"

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private let presetIcons = ["✨", "❤️", "🎮", "📚", "💼", "🎵", "🌟", "🔥", "🎯", "🧠"]
    private let presetColors = [
        "#FF6B9D", "#8B5CF6", "#3B82F6", "#10B981", "#F59E0B", "#EC4899", "#06B6D4", "#EF4444"
    ]

    var body: some View {
        Form {
            Section(isZh ? "新建分组" : "New Group") {
                TextField(isZh ? "英文名" : "English name", text: $draftNameEn)
                TextField(isZh ? "中文名" : "Chinese name", text: $draftNameZh)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        ForEach(presetIcons, id: \.self) { icon in
                            Button {
                                draftIcon = icon
                            } label: {
                                Text(icon)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        draftIcon == icon ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: DSRadius.sm)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        ForEach(presetColors, id: \.self) { color in
                            Button {
                                draftColor = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(draftColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, DSSpacing.xxs)
                }

                Button(isZh ? "添加分组" : "Add Group") {
                    let en = draftNameEn.trimmingCharacters(in: .whitespacesAndNewlines)
                    let zh = draftNameZh.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !en.isEmpty || !zh.isEmpty else { return }
                    friendService.addGroup(
                        name: en.isEmpty ? zh : en,
                        nameZh: zh.isEmpty ? en : zh,
                        colorHex: draftColor,
                        icon: draftIcon
                    )
                    draftNameEn = ""
                    draftNameZh = ""
                }
            }

            Section(isZh ? "已有分组" : "Existing Groups") {
                if friendService.groups.isEmpty {
                    Text(isZh ? "暂无分组" : "No groups")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friendService.groups) { group in
                        HStack(spacing: DSSpacing.sm) {
                            Text(group.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isZh ? group.nameZh : group.name)
                                    .font(DSTypography.footnote.weight(.semibold))
                                Text(group.name)
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle().fill(Color(hex: group.colorHex)).frame(width: 14, height: 14)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                friendService.deleteGroup(id: group.id)
                            } label: {
                                Label(isZh ? "删除" : "Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(isZh ? "好友分组" : "Friend Groups")
        .navigationBarTitleDisplayMode(.inline)
    }
}
