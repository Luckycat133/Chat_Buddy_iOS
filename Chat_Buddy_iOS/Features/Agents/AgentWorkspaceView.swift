import SwiftUI

struct AgentWorkspaceView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    let agent: Persona

    @State private var topicName = ""

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var sessions: [ChatSession] {
        chatStore.sessions
            .filter { !$0.isGroup && $0.primaryPersonaId == agent.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            // Agent skills
            let skills = AgentSkillStore.getSkillsForAgent(agentId: agent.id)
            if !skills.isEmpty {
                Section(isZh ? "技能" : "Skills") {
                    ForEach(skills, id: \.id) { skill in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isZh ? skill.nameZh : skill.name)
                                    .font(DSTypography.footnote.weight(.semibold))
                                Text(skill.description)
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(AgentSkillStore.categoryLabel(skill.category, isZh: isZh))
                                .font(.system(size: 9))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(isZh ? "新话题" : "New Topic") {
                TextField(isZh ? "输入话题名称" : "Topic name", text: $topicName)
                Button(isZh ? "创建" : "Create") {
                    let name = topicName.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = chatStore.createTopicSession(for: agent.id, topicName: name.isEmpty ? nil : name)
                    topicName = ""
                }
            }

            Section(isZh ? "会话列表" : "Conversations") {
                if sessions.isEmpty {
                    Text(isZh ? "暂无会话" : "No conversations")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        NavigationLink {
                            ChatView(sessionId: session.id, persona: agent)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.groupName?.isEmpty == false
                                     ? (session.groupName ?? "")
                                     : (isZh ? "新话题" : "New Topic"))
                                    .font(DSTypography.footnote.weight(.semibold))
                                Text(session.lastMessage?.content ?? (isZh ? "暂无消息" : "No messages"))
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(session.updatedAt, style: .relative)
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(agent.localizedName(language: localization.uiLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }
}
