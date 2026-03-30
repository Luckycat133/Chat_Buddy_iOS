import SwiftUI

struct ForwardMessageSheet: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let message: ChatMessage
    let sourceSessionId: String
    let onForward: ([String]) -> Void

    @State private var selectedSessionIds: Set<String> = []

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var sessions: [ChatSession] {
        chatStore.sessions.filter { $0.id != sourceSessionId }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(isZh ? "转发内容" : "Message")
                            .font(DSTypography.caption1)
                            .foregroundStyle(.secondary)
                        Text(message.content)
                            .font(DSTypography.footnote)
                            .lineLimit(3)
                    }
                    .padding(.vertical, DSSpacing.xxs)
                }

                Section {
                    if sessions.isEmpty {
                        Text(isZh ? "暂无可转发的会话" : "No available conversations")
                            .font(DSTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { session in
                            Button {
                                toggle(session.id)
                            } label: {
                                HStack(spacing: DSSpacing.sm) {
                                    SessionAvatarView(personas: sessionPersonas(session), size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sessionTitle(session))
                                            .font(DSTypography.footnote.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(session.lastMessage?.content ?? (isZh ? "暂无消息" : "No messages"))
                                            .font(DSTypography.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: selectedSessionIds.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedSessionIds.contains(session.id) ? Color.accentColor : .secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(isZh ? "选择会话" : "Select Conversations")
                }
            }
            .navigationTitle(isZh ? "转发消息" : "Forward Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isZh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZh ? "发送" : "Forward") {
                        onForward(Array(selectedSessionIds))
                        dismiss()
                    }
                    .disabled(selectedSessionIds.isEmpty)
                }
            }
        }
    }

    private func toggle(_ sessionId: String) {
        if selectedSessionIds.contains(sessionId) {
            selectedSessionIds.remove(sessionId)
        } else {
            selectedSessionIds.insert(sessionId)
        }
    }

    private func sessionTitle(_ session: ChatSession) -> String {
        if let groupName = session.groupName, !groupName.isEmpty {
            return groupName
        }
        let names = session.personaIds.compactMap { PersonaStore.persona(byId: $0)?.localizedName(language: localization.uiLanguage) }
        return names.isEmpty ? (isZh ? "会话" : "Chat") : names.joined(separator: ", ")
    }

    private func sessionPersonas(_ session: ChatSession) -> [Persona] {
        let persons = session.personaIds.compactMap { PersonaStore.persona(byId: $0) }
        if persons.isEmpty, let fallback = PersonaStore.persona(byId: session.primaryPersonaId) {
            return [fallback]
        }
        return persons
    }
}
