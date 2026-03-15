import SwiftUI

// MARK: - Navigation Destination

struct ChatDestination: Hashable {
    let sessionId: String
    /// Primary persona for title/toolbar rendering. In group chats, this is the first member.
    let persona: Persona

    func hash(into hasher: inout Hasher) { hasher.combine(sessionId) }
    static func == (lhs: ChatDestination, rhs: ChatDestination) -> Bool { lhs.sessionId == rhs.sessionId }
}

// MARK: - Chats Root View

/// Chat list — supports both 1v1 and group sessions.
struct ChatsView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    @State private var showPersonaPicker = false
    @State private var showGroupPicker = false
    @State private var navigationPath = NavigationPath()

    private var pinnedSessions: [ChatSession] { chatStore.sessions.filter { $0.isPinned } }
    private var unpinnedSessions: [ChatSession] { chatStore.sessions.filter { !$0.isPinned } }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if chatStore.sessions.isEmpty { emptyState } else { sessionList }
            }
            .navigationTitle(localization.t("nav_chats"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showPersonaPicker = true
                        } label: {
                            Label(localization.t("chats_new_chat"), systemImage: "person.crop.circle.badge.plus")
                        }
                        Button {
                            showGroupPicker = true
                        } label: {
                            Label(localization.t("chats_new_group"), systemImage: "person.3.fill")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(for: ChatDestination.self) { dest in
                ChatView(sessionId: dest.sessionId, persona: dest.persona)
            }
            .sheet(isPresented: $showPersonaPicker) {
                PersonaPickerSheet(navigationPath: $navigationPath, isPresented: $showPersonaPicker)
            }
            .sheet(isPresented: $showGroupPicker) {
                GroupPickerSheet(navigationPath: $navigationPath, isPresented: $showGroupPicker)
            }
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.xxs) {
                // Pinned section
                if !pinnedSessions.isEmpty {
                    sectionHeader(localization.t("chats_pinned"), systemImage: "pin.fill")
                    ForEach(pinnedSessions) { session in
                        if let persona = PersonaStore.persona(byId: session.personaId) {
                            sessionRow(session: session, persona: persona)
                        }
                    }
                }
                // Unpinned section
                ForEach(unpinnedSessions) { session in
                    if let persona = PersonaStore.persona(byId: session.personaId) {
                        sessionRow(session: session, persona: persona)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(title)
                .font(DSTypography.caption1.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.top, DSSpacing.sm)
    }

    private func sessionRow(session: ChatSession, persona: Persona) -> some View {
        let personas = session.personaIds.compactMap { PersonaStore.persona(byId: $0) }
        return ChatSessionRow(
            session: session,
            personas: personas.isEmpty ? [persona] : personas,
            localization: localization
        )
        .contentShape(Rectangle())
        .onTapGesture {
            navigationPath.append(ChatDestination(sessionId: session.id, persona: persona))
        }
        .contextMenu {
            if session.isPinned {
                Button { chatStore.unpinSession(id: session.id) } label: {
                    Label(localization.t("chat_unpin"), systemImage: "pin.slash")
                }
            } else {
                Button { chatStore.pinSession(id: session.id) } label: {
                    Label(localization.t("chat_pin"), systemImage: "pin")
                }
            }
            Divider()
            Button(role: .destructive) {
                withAnimation { chatStore.deleteSession(session) }
            } label: {
                Label(localization.t("chats_delete"), systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: DSSpacing.xs) {
                Text(localization.t("chats_empty_title"))
                    .font(DSTypography.title3)
                Text(localization.t("chats_empty_desc"))
                    .font(DSTypography.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showPersonaPicker = true
            } label: {
                Label(localization.t("chats_new_chat"), systemImage: "plus")
                    .padding(.horizontal, DSSpacing.lg)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(DSSpacing.xxl)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Chat Session Row

private struct ChatSessionRow: View {
    let session: ChatSession
    let personas: [Persona]
    let localization: LocalizationManager

    /// Display title: group name → joined persona names → single persona name
    private var displayTitle: String {
        if let name = session.groupName, !name.isEmpty { return name }
        return personas.map { $0.name }.joined(separator: ", ")
    }

    var body: some View {
        GlassCard(cornerRadius: DSRadius.md) {
            HStack(spacing: DSSpacing.sm) {
                SessionAvatarView(personas: personas, size: 48)

                VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(displayTitle)
                            .font(DSTypography.headline)
                            .lineLimit(1)
                        if session.isGroup {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if session.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(relativeTime(session.updatedAt))
                            .font(DSTypography.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(session.lastMessage?.content ?? localization.t("chats_no_messages"))
                        .font(DSTypography.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(DSSpacing.sm)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return Self.timeFormatter.string(from: date) }
        if calendar.isDateInYesterday(date) { return localization.t("chats_yesterday") }
        return Self.shortDateFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; return f
    }()
}

// MARK: - Persona Picker Sheet

struct PersonaPickerSheet: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    @Binding var navigationPath: NavigationPath
    @Binding var isPresented: Bool

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    personaSection(
                        title: localization.t("personas_social"),
                        personas: PersonaStore.socialCompanions
                    )
                    personaSection(
                        title: localization.t("personas_task"),
                        personas: PersonaStore.taskAgents
                    )
                }
                .padding(DSSpacing.md)
            }
            .navigationTitle(localization.t("chats_new_chat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func personaSection(title: String, personas: [Persona]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(title)
                .font(DSTypography.headline)
                .padding(.leading, DSSpacing.xs)

            LazyVGrid(columns: columns, spacing: DSSpacing.sm) {
                ForEach(personas) { persona in
                    PersonaPickerCell(
                        persona: persona,
                        localization: localization,
                        onTap: {
                            let session = chatStore.getOrCreateSession(for: persona.id)
                            let dest = ChatDestination(sessionId: session.id, persona: persona)
                            isPresented = false
                            // Brief delay lets sheet dismiss before navigation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                navigationPath.append(dest)
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Persona Picker Cell

private struct PersonaPickerCell: View {
    let persona: Persona
    let localization: LocalizationManager
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DSSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(persona.accentColor.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Circle()
                        .strokeBorder(persona.accentColor.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 56, height: 56)
                    Text(String(persona.name.prefix(1)))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(persona.accentColor)
                }

                Text(persona.localizedName(language: localization.uiLanguage))
                    .font(DSTypography.caption1)
                    .lineLimit(1)

                Text(
                    persona.localizedPersonality(language: localization.uiLanguage)
                        .components(separatedBy: ",").first?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                )
                .font(DSTypography.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.md))
        }
        .buttonStyle(.plain)
    }
}
