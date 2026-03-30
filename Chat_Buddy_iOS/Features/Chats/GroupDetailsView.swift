import SwiftUI

struct GroupDetailsView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    let sessionId: String

    @State private var draftGroupName = ""
    @State private var announcementText = ""
    @State private var showAddMembers = false
    @State private var showPollComposer = false

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var session: ChatSession? {
        chatStore.session(id: sessionId)
    }

    private var participants: [Persona] {
        (session?.personaIds ?? []).compactMap { PersonaStore.persona(byId: $0) }
    }

    var body: some View {
        Form {
            if let session {
                Section(isZh ? "群信息" : "Group Info") {
                    TextField(isZh ? "群名称" : "Group name", text: $draftGroupName)
                        .onSubmit {
                            chatStore.updateGroupName(id: sessionId, name: draftGroupName)
                        }

                    if let announcement = session.announcement, !announcement.content.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isZh ? "当前公告" : "Current Announcement")
                                .font(DSTypography.caption1)
                                .foregroundStyle(.secondary)
                            Text(announcement.content)
                                .font(DSTypography.footnote)
                        }
                    }

                    TextField(isZh ? "编辑公告" : "Edit announcement", text: $announcementText, axis: .vertical)
                        .lineLimit(1...3)
                    Button(isZh ? "保存公告" : "Save Announcement") {
                        let content = announcementText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if content.isEmpty {
                            chatStore.updateAnnouncement(sessionId: sessionId, announcement: nil)
                        } else {
                            chatStore.updateAnnouncement(sessionId: sessionId, announcement: GroupAnnouncement(content: content))
                        }
                    }
                }

                Section(isZh ? "成员" : "Members") {
                    ForEach(participants) { persona in
                        HStack(spacing: DSSpacing.sm) {
                            Circle()
                                .fill(persona.accentColor.opacity(0.18))
                                .frame(width: 28, height: 28)
                                .overlay(Text(String(persona.name.prefix(1))).font(.caption).foregroundStyle(persona.accentColor))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(persona.localizedName(language: localization.uiLanguage))
                                if let nick = session.nicknames[persona.id], !nick.isEmpty {
                                    Text(isZh ? "群昵称：\(nick)" : "Nickname: \(nick)")
                                        .font(DSTypography.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }

                    Button(isZh ? "添加成员" : "Add Members") {
                        showAddMembers = true
                    }
                }

                Section(isZh ? "群设置" : "Group Settings") {
                    Toggle(
                        isZh ? "允许表情互动" : "Allow reactions",
                        isOn: Binding(
                            get: { session.permissions.allowReactions },
                            set: { chatStore.updatePermissions(sessionId: sessionId, permissions: ChatPermissions(allowReactions: $0, allowImages: session.permissions.allowImages)) }
                        )
                    )
                    Toggle(
                        isZh ? "允许图片" : "Allow images",
                        isOn: Binding(
                            get: { session.permissions.allowImages },
                            set: { chatStore.updatePermissions(sessionId: sessionId, permissions: ChatPermissions(allowReactions: session.permissions.allowReactions, allowImages: $0)) }
                        )
                    )
                    Toggle(
                        isZh ? "消息免打扰" : "Mute notifications",
                        isOn: Binding(
                            get: { session.isMuted },
                            set: { chatStore.updateMuted(sessionId: sessionId, isMuted: $0) }
                        )
                    )
                    Toggle(
                        isZh ? "仅管理员发言" : "Admin-only chat",
                        isOn: Binding(
                            get: { session.adminOnly },
                            set: { chatStore.updateAdminOnly(sessionId: sessionId, adminOnly: $0) }
                        )
                    )
                }

                Section(isZh ? "投票" : "Polls") {
                    Button(isZh ? "创建投票" : "Create Poll") {
                        showPollComposer = true
                    }

                    if session.polls.isEmpty {
                        Text(isZh ? "暂无投票" : "No polls yet")
                            .font(DSTypography.caption1)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.polls) { poll in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(poll.question)
                                    .font(DSTypography.footnote.weight(.semibold))
                                Text(poll.isExpired
                                     ? (isZh ? "已结束" : "Closed")
                                     : (isZh ? "进行中" : "Active"))
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(poll.isExpired ? .secondary : .green)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text(isZh ? "会话不存在" : "Session not found")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(isZh ? "群聊详情" : "Group Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let session {
                draftGroupName = session.groupName ?? ""
                announcementText = session.announcement?.content ?? ""
            }
        }
        .sheet(isPresented: $showAddMembers) {
            AddGroupMembersSheet(sessionId: sessionId)
        }
        .sheet(isPresented: $showPollComposer) {
            PollComposerView { question, options, multiple, anonymous, hours in
                guard let poll = chatStore.createPoll(
                    in: sessionId,
                    question: question,
                    options: options,
                    allowsMultipleSelection: multiple,
                    isAnonymous: anonymous,
                    expiresInHours: hours
                ) else { return }
                chatStore.appendMessage(ChatMessage(role: .assistant, content: "[POLL:\(poll.id)]"), to: sessionId)
            }
        }
    }
}

private struct AddGroupMembersSheet: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let sessionId: String

    @State private var selected: Set<String> = []

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var session: ChatSession? {
        chatStore.session(id: sessionId)
    }

    private var candidates: [Persona] {
        let existing = Set(session?.personaIds ?? [])
        return PersonaStore.allPersonas.filter { !existing.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { persona in
                    Button {
                        if selected.contains(persona.id) {
                            selected.remove(persona.id)
                        } else {
                            selected.insert(persona.id)
                        }
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            Circle()
                                .fill(persona.accentColor.opacity(0.18))
                                .frame(width: 30, height: 30)
                                .overlay(Text(String(persona.name.prefix(1))).font(.caption).foregroundStyle(persona.accentColor))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(persona.localizedName(language: localization.uiLanguage))
                                    .foregroundStyle(.primary)
                                Text(persona.localizedPersonality(language: localization.uiLanguage))
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: selected.contains(persona.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(persona.id) ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(isZh ? "添加成员" : "Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isZh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZh ? "添加" : "Add") {
                        chatStore.addMembers(sessionId: sessionId, personaIds: Array(selected))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
