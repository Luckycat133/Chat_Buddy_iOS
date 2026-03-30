import SwiftUI

struct FriendsView: View {
    @Environment(FriendService.self) private var friendService
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    @State private var searchText = ""
    @State private var selectedFilter: String = "all"
    @State private var showCreateSheet = false
    @State private var editingPersona: Persona?
    @State private var personaListVersion = 0

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var allPersonas: [Persona] {
        _ = personaListVersion
        return PersonaStore.socialCompanions + PersonaStore.customSocialCompanions
    }

    private var filteredPersonas: [Persona] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allPersonas.filter { persona in
            let meta = friendService.friendMeta(for: persona.id)

            if selectedFilter == "starred", !meta.starred {
                return false
            }
            if selectedFilter != "all" && selectedFilter != "starred" {
                if meta.groupId != selectedFilter { return false }
            }

            if q.isEmpty { return true }
            let name = persona.localizedName(language: localization.uiLanguage)
            return name.localizedCaseInsensitiveContains(q)
                || persona.name.localizedCaseInsensitiveContains(q)
                || persona.nameZh.localizedCaseInsensitiveContains(q)
        }
        .sorted { lhs, rhs in
            let lStar = friendService.friendMeta(for: lhs.id).starred
            let rStar = friendService.friendMeta(for: rhs.id).starred
            if lStar != rStar { return lStar && !rStar }
            return lhs.localizedName(language: localization.uiLanguage) < rhs.localizedName(language: localization.uiLanguage)
        }
    }

    var body: some View {
        List {
            Section {
                TextField(isZh ? "搜索好友" : "Search friends", text: $searchText)
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        filterChip(id: "all", label: isZh ? "全部" : "All")
                        filterChip(id: "starred", label: isZh ? "星标" : "Starred")
                        ForEach(friendService.groups) { group in
                            filterChip(
                                id: group.id,
                                label: "\(group.icon) " + (isZh ? group.nameZh : group.name),
                                tint: Color(hex: group.colorHex)
                            )
                        }
                    }
                    .padding(.vertical, DSSpacing.xxs)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            Section {
                if filteredPersonas.isEmpty {
                    Text(isZh ? "没有匹配的好友" : "No matching friends")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredPersonas) { persona in
                        let session = chatStore.getOrCreateSession(for: persona.id)
                        let meta = friendService.friendMeta(for: persona.id)

                        NavigationLink {
                            ChatView(sessionId: session.id, persona: persona)
                        } label: {
                            HStack(spacing: DSSpacing.sm) {
                                Circle()
                                    .fill(persona.accentColor.opacity(0.18))
                                    .frame(width: 38, height: 38)
                                    .overlay(Text(String(persona.name.prefix(1))).font(.footnote).foregroundStyle(persona.accentColor))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(persona.localizedName(language: localization.uiLanguage))
                                            .font(DSTypography.footnote.weight(.semibold))
                                        if meta.starred {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.yellow)
                                        }
                                    }

                                    if let gid = meta.groupId,
                                       let group = friendService.groups.first(where: { $0.id == gid }) {
                                        Text("\(group.icon) " + (isZh ? group.nameZh : group.name))
                                            .font(DSTypography.caption2)
                                            .foregroundStyle(Color(hex: group.colorHex))
                                    } else {
                                        Text(persona.localizedPersonality(language: localization.uiLanguage))
                                            .font(DSTypography.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .contextMenu {
                            Button {
                                friendService.toggleStar(for: persona.id)
                            } label: {
                                Label(
                                    meta.starred
                                    ? (isZh ? "取消星标" : "Unstar")
                                    : (isZh ? "设为星标" : "Star"),
                                    systemImage: meta.starred ? "star.slash" : "star"
                                )
                            }

                            Menu(isZh ? "分组" : "Group") {
                                Button(isZh ? "未分组" : "Ungrouped") {
                                    friendService.assignGroup(nil, for: persona.id)
                                }
                                ForEach(friendService.groups) { group in
                                    Button("\(group.icon) " + (isZh ? group.nameZh : group.name)) {
                                        friendService.assignGroup(group.id, for: persona.id)
                                    }
                                }
                            }

                            if isCustomPersona(persona) {
                                Button {
                                    editingPersona = persona
                                } label: {
                                    Label(isZh ? "编辑自定义好友" : "Edit custom friend", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    PersonaStore.deleteCustomPersona(id: persona.id)
                                    personaListVersion += 1
                                } label: {
                                    Label(isZh ? "删除自定义好友" : "Delete custom friend", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(localization.t("friends"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    FriendGroupsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CustomPersonaEditorSheet(agentType: .socialCompanion) { persona in
                PersonaStore.upsertCustomPersona(persona)
                personaListVersion += 1
            }
        }
        .sheet(item: $editingPersona) { persona in
            CustomPersonaEditorSheet(agentType: .socialCompanion, editingPersona: persona) { updated in
                PersonaStore.upsertCustomPersona(updated)
                personaListVersion += 1
            }
        }
    }

    private func filterChip(id: String, label: String, tint: Color = .accentColor) -> some View {
        Button {
            selectedFilter = id
        } label: {
            Text(label)
                .font(DSTypography.caption1.weight(.semibold))
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, 6)
                .background(
                    selectedFilter == id ? tint : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(selectedFilter == id ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func isCustomPersona(_ persona: Persona) -> Bool {
        PersonaStore.customSocialCompanions.contains { $0.id == persona.id }
    }
}
