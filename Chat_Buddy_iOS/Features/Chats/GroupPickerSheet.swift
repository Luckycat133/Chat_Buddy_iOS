import SwiftUI

/// Sheet for creating a new group chat by selecting 2+ personas.
struct GroupPickerSheet: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    @Binding var navigationPath: NavigationPath
    @Binding var isPresented: Bool

    @State private var selectedIds: Set<String> = []
    @State private var groupName: String = ""

    private var canCreate: Bool { selectedIds.count >= 2 }

    var body: some View {
        NavigationStack {
            List {
                // Optional group name field
                Section {
                    TextField(localization.t("chats_group_name_placeholder"), text: $groupName)
                        .font(DSTypography.body)
                } header: {
                    Text(localization.t("chats_group_name"))
                        .font(DSTypography.caption1)
                }

                // Persona selection
                Section {
                    ForEach(PersonaStore.socialCompanions) { persona in
                        personaRow(persona)
                    }
                } header: {
                    Text(localization.t("personas_social"))
                        .font(DSTypography.caption1)
                }

                Section {
                    ForEach(PersonaStore.taskAgents) { persona in
                        personaRow(persona)
                    }
                } header: {
                    Text(localization.t("personas_task"))
                        .font(DSTypography.caption1)
                }
            }
            .navigationTitle(localization.t("chats_new_group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.t("chats_create_group")) {
                        createGroup()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedIds.isEmpty {
                    selectedBanner
                }
            }
        }
    }

    // MARK: - Persona Row

    private func personaRow(_ persona: Persona) -> some View {
        let isSelected = selectedIds.contains(persona.id)
        return HStack(spacing: DSSpacing.sm) {
            // Mini avatar
            ZStack {
                Circle().fill(persona.accentColor.opacity(0.18))
                Text(String(persona.name.prefix(1)))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(persona.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(persona.localizedName(language: localization.uiLanguage))
                    .font(DSTypography.body)
                Text(persona.localizedPersonality(language: localization.uiLanguage)
                     .components(separatedBy: ",").first?
                     .trimmingCharacters(in: .whitespaces) ?? "")
                    .font(DSTypography.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? persona.accentColor : .secondary)
                .font(.title3)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25)) {
                if isSelected { selectedIds.remove(persona.id) }
                else { selectedIds.insert(persona.id) }
            }
        }
    }

    // MARK: - Selected Banner

    private var selectedBanner: some View {
        HStack(spacing: DSSpacing.sm) {
            // Stack of mini avatars (up to 4)
            HStack(spacing: -10) {
                ForEach(Array(selectedIds.prefix(4)), id: \.self) { pid in
                    if let p = PersonaStore.persona(byId: pid) {
                        ZStack {
                            Circle().fill(p.accentColor.opacity(0.25))
                                .frame(width: 30, height: 30)
                            Text(String(p.name.prefix(1)))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(p.accentColor)
                        }
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    }
                }
            }

            Text(localization.t("chats_selected_count")
                 .replacingOccurrences(of: "{n}", with: "\(selectedIds.count)"))
                .font(DSTypography.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.3)
        }
    }

    // MARK: - Action

    private func createGroup() {
        guard canCreate else { return }
        let ids = Array(selectedIds)
        let name = groupName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : groupName
        let session = chatStore.createGroupSession(personaIds: ids, groupName: name)
        let primaryPersona = PersonaStore.persona(byId: ids[0]) ?? PersonaStore.socialCompanions[0]
        let dest = ChatDestination(sessionId: session.id, persona: primaryPersona)
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            navigationPath.append(dest)
        }
    }
}
