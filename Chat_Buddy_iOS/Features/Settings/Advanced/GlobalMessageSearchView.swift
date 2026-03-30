import SwiftUI

private struct MessageSearchResult: Identifiable {
    let id: String
    let sessionId: String
    let sessionTitle: String
    let persona: Persona
    let message: ChatMessage
}

struct GlobalMessageSearchView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    @State private var query = ""

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var results: [MessageSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return chatStore.sessions.flatMap { session in
            let title = sessionTitle(session)
            let fallbackPersona = PersonaStore.persona(byId: session.primaryPersonaId) ?? PersonaStore.socialCompanions[0]

            return session.displayMessages
                .filter { $0.content.localizedCaseInsensitiveContains(q) }
                .map {
                    MessageSearchResult(
                        id: "\(session.id)-\($0.id)",
                        sessionId: session.id,
                        sessionTitle: title,
                        persona: fallbackPersona,
                        message: $0
                    )
                }
        }
        .sorted { $0.message.timestamp > $1.message.timestamp }
    }

    var body: some View {
        List {
            Section {
                TextField(
                    isZh ? "搜索所有会话消息" : "Search all messages",
                    text: $query
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Text(isZh ? "输入关键词开始搜索" : "Type keywords to search")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                }
            } else if results.isEmpty {
                Section {
                    Text(isZh ? "未找到匹配消息" : "No matching messages")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(isZh ? "搜索结果" : "Results") {
                    ForEach(results) { result in
                        NavigationLink {
                            ChatView(
                                sessionId: result.sessionId,
                                persona: result.persona,
                                initialFocusMessageId: result.message.id
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.sessionTitle)
                                    .font(DSTypography.caption1.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(result.message.content)
                                    .font(DSTypography.footnote)
                                    .lineLimit(2)
                                Text(result.message.timestamp, style: .relative)
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle(isZh ? "全局搜索" : "Global Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sessionTitle(_ session: ChatSession) -> String {
        if let groupName = session.groupName, !groupName.isEmpty {
            return groupName
        }
        let names = session.personaIds.compactMap { PersonaStore.persona(byId: $0)?.localizedName(language: localization.uiLanguage) }
        return names.isEmpty ? (isZh ? "会话" : "Chat") : names.joined(separator: ", ")
    }
}
