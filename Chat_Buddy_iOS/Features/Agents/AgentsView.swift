import SwiftUI

struct AgentsView: View {
    @Environment(LocalizationManager.self) private var localization

    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var editingPersona: Persona?
    @State private var personaListVersion = 0
    @State private var personaToDelete: Persona?

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var filteredAgents: [Persona] {
        _ = personaListVersion
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let allAgents = PersonaStore.taskAgents + PersonaStore.customTaskAgents
        return allAgents.filter { agent in
            guard !q.isEmpty else { return true }
            return agent.localizedName(language: localization.uiLanguage).localizedCaseInsensitiveContains(q)
                || agent.name.localizedCaseInsensitiveContains(q)
                || agent.nameZh.localizedCaseInsensitiveContains(q)
                || agent.personality.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            Section {
                TextField(isZh ? "搜索智能体" : "Search agents", text: $searchText)
            }

            Section {
                if filteredAgents.isEmpty {
                    Text(isZh ? "未找到匹配智能体" : "No matching agents")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredAgents) { agent in
                        NavigationLink {
                            AgentWorkspaceView(agent: agent)
                        } label: {
                            HStack(spacing: DSSpacing.sm) {
                                Circle()
                                    .fill(agent.accentColor.opacity(0.18))
                                    .frame(width: 38, height: 38)
                                    .overlay(Text(String(agent.name.prefix(1))).font(.footnote).foregroundStyle(agent.accentColor))
                                    .overlay(alignment: .bottomTrailing) {
                                        let status = PresenceService.getStatus(for: agent.id)
                                        Circle()
                                            .fill(status.swiftUIColor)
                                            .frame(width: 10, height: 10)
                                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.localizedName(language: localization.uiLanguage))
                                        .font(DSTypography.footnote.weight(.semibold))
                                    Text(agent.localizedPersonality(language: localization.uiLanguage))
                                        .font(DSTypography.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    // Agent skills badges
                                    let skills = AgentSkillStore.getSkillsForAgent(agentId: agent.id)
                                    if !skills.isEmpty {
                                        HStack(spacing: 4) {
                                            ForEach(skills.prefix(3), id: \.id) { skill in
                                                Text(isZh ? skill.nameZh : skill.name)
                                                    .font(.system(size: 9))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .contextMenu {
                            if isCustomAgent(agent) {
                                Button {
                                    editingPersona = agent
                                } label: {
                                    Label(isZh ? "编辑自定义智能体" : "Edit custom agent", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    personaToDelete = agent
                                } label: {
                                    Label(isZh ? "删除自定义智能体" : "Delete custom agent", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(localization.t("ai_agents"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CustomPersonaEditorSheet(agentType: .taskSpecialist) { persona in
                PersonaStore.upsertCustomPersona(persona)
                personaListVersion += 1
            }
        }
        .sheet(item: $editingPersona) { persona in
            CustomPersonaEditorSheet(agentType: .taskSpecialist, editingPersona: persona) { updated in
                PersonaStore.upsertCustomPersona(updated)
                personaListVersion += 1
            }
        }
        .alert(localization.t("delete_confirm_title"), isPresented: .init(
            get: { personaToDelete != nil },
            set: { if !$0 { personaToDelete = nil } }
        )) {
            Button(localization.t("delete"), role: .destructive) {
                if let persona = personaToDelete {
                    PersonaStore.deleteCustomPersona(id: persona.id)
                    personaListVersion += 1
                    personaToDelete = nil
                }
            }
            Button(localization.t("cancel"), role: .cancel) {
                personaToDelete = nil
            }
        } message: {
            Text(localization.t("delete_confirm_message"))
        }
    }

    private func isCustomAgent(_ persona: Persona) -> Bool {
        PersonaStore.customTaskAgents.contains { $0.id == persona.id }
    }
}
