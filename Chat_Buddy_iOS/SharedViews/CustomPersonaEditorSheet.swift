import SwiftUI

struct CustomPersonaEditorSheet: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let agentType: AgentType
    let editingPersona: Persona?
    let onSave: (Persona) -> Void

    @State private var name = ""
    @State private var nameZh = ""
    @State private var personality = ""
    @State private var personalityZh = ""
    @State private var style = ""
    @State private var styleZh = ""
    @State private var selectedCategory: AgentCategory = .productivity

    private var isZh: Bool { localization.uiLanguage.resolved == AppLanguage.zh }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNameZh = nameZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPersonality = personality.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPersonalityZh = personalityZh.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmedName.isEmpty || !trimmedNameZh.isEmpty)
            && trimmedName.count <= 30
            && (!trimmedPersonality.isEmpty || !trimmedPersonalityZh.isEmpty)
    }

    private var nameExceedsLimit: Bool {
        name.count > 30
    }

    init(agentType: AgentType, editingPersona: Persona? = nil, onSave: @escaping (Persona) -> Void) {
        self.agentType = agentType
        self.editingPersona = editingPersona
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(localization.t("custom_persona_section_basics")) {
                    TextField(localization.t("custom_persona_name_en"), text: $name)
                    if nameExceedsLimit {
                        Text(isZh ? "名称不能超过30个字符" : "Name must be 30 characters or less")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField(localization.t("custom_persona_name_zh"), text: $nameZh)
                }

                Section(localization.t("custom_persona_section_personality")) {
                    TextField(localization.t("custom_persona_personality_en"), text: $personality, axis: .vertical)
                        .lineLimit(1...3)
                    TextField(localization.t("custom_persona_personality_zh"), text: $personalityZh, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section(localization.t("custom_persona_section_style")) {
                    TextField(localization.t("custom_persona_style_en"), text: $style, axis: .vertical)
                        .lineLimit(1...2)
                    TextField(localization.t("custom_persona_style_zh"), text: $styleZh, axis: .vertical)
                        .lineLimit(1...2)
                }

                if agentType == .taskSpecialist {
                    Section(localization.t("custom_persona_section_category")) {
                        Picker("", selection: $selectedCategory) {
                            Text(localization.t("category_productivity")).tag(AgentCategory.productivity)
                            Text(localization.t("category_education")).tag(AgentCategory.education)
                            Text(localization.t("category_wellbeing")).tag(AgentCategory.wellbeing)
                            Text(localization.t("category_creative")).tag(AgentCategory.creative)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localization.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.t("save")) {
                        buildAndSavePersona()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                guard let editingPersona else { return }
                name = editingPersona.name
                nameZh = editingPersona.nameZh
                personality = editingPersona.personality
                personalityZh = editingPersona.personalityZh
                style = editingPersona.style
                styleZh = editingPersona.styleZh
                if let category = editingPersona.category {
                    selectedCategory = category
                }
            }
        }
    }

    private var navigationTitle: String {
        if editingPersona != nil {
            return agentType == .socialCompanion
                ? localization.t("custom_persona_edit_friend")
                : localization.t("custom_persona_edit_agent")
        }
        return agentType == .socialCompanion
            ? localization.t("custom_persona_create_friend")
            : localization.t("custom_persona_create_agent")
    }

    private func buildAndSavePersona() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNameZh = nameZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPersonality = personality.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPersonalityZh = personalityZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStyle = style.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStyleZh = styleZh.trimmingCharacters(in: .whitespacesAndNewlines)

        let newPersona = Persona(
            id: editingPersona?.id ?? makeId(),
            name: trimmedName,
            nameZh: trimmedNameZh.isEmpty ? trimmedName : trimmedNameZh,
            avatar: editingPersona?.avatar ?? "default_abstract",
            birthday: editingPersona?.birthday,
            personality: trimmedPersonality,
            personalityZh: trimmedPersonalityZh.isEmpty ? trimmedPersonality : trimmedPersonalityZh,
            interests: editingPersona?.interests ?? ["Custom"],
            interestsZh: editingPersona?.interestsZh ?? ["自定义"],
            style: trimmedStyle.isEmpty ? "Friendly" : trimmedStyle,
            styleZh: trimmedStyleZh.isEmpty ? "友好" : trimmedStyleZh,
            agentType: agentType,
            category: agentType == .taskSpecialist ? selectedCategory : nil
        )
        onSave(newPersona)
        dismiss()
    }

    private func makeId() -> String {
        let prefix = agentType == .socialCompanion ? "custom-social" : "custom-agent"
        return "\(prefix)-\(UUID().uuidString.prefix(8))"
    }
}
