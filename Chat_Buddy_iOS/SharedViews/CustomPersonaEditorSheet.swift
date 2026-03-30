import SwiftUI

struct CustomPersonaEditorSheet: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let agentType: AgentType
    let editingPersona: Persona? = nil
    let onSave: (Persona) -> Void

    @State private var name = ""
    @State private var nameZh = ""
    @State private var personality = ""
    @State private var personalityZh = ""
    @State private var style = ""
    @State private var styleZh = ""
    @State private var selectedCategory: AgentCategory = .productivity

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !personality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isZh ? "基础信息" : "Basics") {
                    TextField(isZh ? "名称（英文）" : "Name (English)", text: $name)
                    TextField(isZh ? "名称（中文）" : "Name (Chinese)", text: $nameZh)
                }

                Section(isZh ? "人格设定" : "Personality") {
                    TextField(isZh ? "人格（英文）" : "Personality (English)", text: $personality, axis: .vertical)
                        .lineLimit(1...3)
                    TextField(isZh ? "人格（中文）" : "Personality (Chinese)", text: $personalityZh, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section(isZh ? "对话风格" : "Style") {
                    TextField(isZh ? "风格（英文）" : "Style (English)", text: $style, axis: .vertical)
                        .lineLimit(1...2)
                    TextField(isZh ? "风格（中文）" : "Style (Chinese)", text: $styleZh, axis: .vertical)
                        .lineLimit(1...2)
                }

                if agentType == .taskSpecialist {
                    Section(isZh ? "类型" : "Category") {
                        Picker("", selection: $selectedCategory) {
                            Text(isZh ? "效率" : "Productivity").tag(AgentCategory.productivity)
                            Text(isZh ? "教育" : "Education").tag(AgentCategory.education)
                            Text(isZh ? "健康" : "Wellbeing").tag(AgentCategory.wellbeing)
                            Text(isZh ? "创意" : "Creative").tag(AgentCategory.creative)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isZh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZh ? "保存" : "Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedNameZh = nameZh.trimmingCharacters(in: .whitespacesAndNewlines)
                        let newPersona = Persona(
                            id: editingPersona?.id ?? makeId(),
                            name: trimmedName,
                            nameZh: trimmedNameZh.isEmpty ? trimmedName : trimmedNameZh,
                            avatar: editingPersona?.avatar ?? "default_abstract",
                            birthday: editingPersona?.birthday,
                            personality: personality.trimmingCharacters(in: .whitespacesAndNewlines),
                            personalityZh: personalityZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? personality.trimmingCharacters(in: .whitespacesAndNewlines)
                                : personalityZh.trimmingCharacters(in: .whitespacesAndNewlines),
                            interests: editingPersona?.interests ?? ["Custom"],
                            interestsZh: editingPersona?.interestsZh ?? ["自定义"],
                            style: style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Friendly" : style.trimmingCharacters(in: .whitespacesAndNewlines),
                            styleZh: styleZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "友好" : styleZh.trimmingCharacters(in: .whitespacesAndNewlines),
                            agentType: agentType,
                            category: agentType == .taskSpecialist ? selectedCategory : nil
                        )
                        onSave(newPersona)
                        dismiss()
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
                ? (isZh ? "编辑自定义好友" : "Edit Friend")
                : (isZh ? "编辑自定义智能体" : "Edit Agent")
        }
        return agentType == .socialCompanion
            ? (isZh ? "创建自定义好友" : "Create Friend")
            : (isZh ? "创建自定义智能体" : "Create Agent")
    }

    private func makeId() -> String {
        let prefix = agentType == .socialCompanion ? "custom-social" : "custom-agent"
        return "\(prefix)-\(UUID().uuidString.prefix(8))"
    }
}
