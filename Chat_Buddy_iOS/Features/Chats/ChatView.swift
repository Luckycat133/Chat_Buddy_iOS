import SwiftUI

/// Individual chat conversation screen
struct ChatView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(APIConfigStore.self) private var apiConfigStore
    @Environment(LocalizationManager.self) private var localization
    @Environment(AffinityService.self) private var affinityService
    @Environment(BookmarkService.self) private var bookmarkService
    @Environment(DraftService.self) private var draftService
    @Environment(AccentColorManager.self) private var accentManager
    @Environment(BackgroundStore.self) private var backgroundStore
    @Environment(SocialService.self) private var socialService
    @Environment(MemoryService.self) private var memoryService
    @Environment(ToolExecutorService.self) private var toolExecutorService

    let sessionId: String
    let persona: Persona

    @State private var viewModel = ChatViewModel()
    @State private var showClearAlert = false
    @State private var showBookmarks = false
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var scrollToMessageId: String? = nil
    @State private var showGift = false
    @State private var showGame = false
    @State private var gameType: GameType = .rps
    @State private var showMemories = false

    enum GameType { case rps, numberGuess }

    private var session: ChatSession? { chatStore.session(id: sessionId) }
    private var allMessages: [ChatMessage] { session?.displayMessages ?? [] }
    private var isGroup: Bool { session?.isGroup ?? false }
    private var groupPersonas: [Persona] {
        (session?.personaIds ?? [persona.id]).compactMap { PersonaStore.persona(byId: $0) }
    }
    private var groupTitle: String {
        guard let sess = session else { return persona.localizedName(language: localization.uiLanguage) }
        if let name = sess.groupName, !name.isEmpty { return name }
        if sess.isGroup { return groupPersonas.map { $0.name }.joined(separator: ", ") }
        return persona.localizedName(language: localization.uiLanguage)
    }
    private var messages: [ChatMessage] {
        if showSearch && !searchQuery.isEmpty {
            return chatStore.searchMessages(query: searchQuery, in: sessionId)
        }
        return allMessages
    }
    private var quotedMessage: ChatMessage? {
        guard let id = viewModel.quotedMessageId else { return nil }
        return allMessages.first { $0.id == id }
    }
    private var quotedSenderName: String {
        guard let q = quotedMessage else { return "" }
        if q.role == .user { return "You" }
        if let pid = q.speakingPersonaId, let p = PersonaStore.persona(byId: pid) {
            return p.localizedName(language: localization.uiLanguage)
        }
        return persona.localizedName(language: localization.uiLanguage)
    }
    private var quotedAccentColor: Color {
        guard let q = quotedMessage else { return accentManager.currentColor }
        if q.role == .user { return accentManager.currentColor }
        if let pid = q.speakingPersonaId { return PersonaStore.colorMap[pid] ?? persona.accentColor }
        return persona.accentColor
    }
    private var currentMood: MoodService.Mood { MoodService.currentMood(for: persona) }
    private var isZhUI: Bool { localization.uiLanguage.resolved == .zh }
    private var currentScore: Int { affinityService.score(for: persona.id) }
    private var currentLevel: AffinityLevel { affinityService.level(for: persona.id) }

    var body: some View {
        ZStack {
            // Animated wallpaper layer (gradient + optional particles)
            AnimatedBackgroundView(
                preset: backgroundStore.resolvedPreset(for: sessionId),
                animation: backgroundStore.resolvedAnimation(for: sessionId)
            )

            VStack(spacing: 0) {
            // In-chat search bar
            if showSearch {
                searchBar
            }

            messageList

            // Error banner
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(DSTypography.caption1)
                    .foregroundStyle(.white)
                    .padding(DSSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            MessageInputView(
                text: $viewModel.inputText,
                placeholder: localization.t("chat_input_placeholder"),
                isDisabled: viewModel.isTyping,
                onSend: send,
                quotedMessage: quotedMessage,
                quotedSenderName: quotedSenderName,
                quotedAccentColor: quotedAccentColor,
                onClearQuote: { viewModel.quotedMessageId = nil }
            )
            } // end inner VStack
        } // end ZStack
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showBookmarks = true
                } label: {
                    Image(systemName: bookmarkService.bookmarks.contains { $0.sessionId == sessionId } ? "bookmark.fill" : "bookmark")
                }
            }
            ToolbarItem(placement: .principal) {
                if isGroup {
                    // Group chat: show title + member count + stacked mini avatars
                    VStack(spacing: 1) {
                        Text(groupTitle)
                            .font(DSTypography.headline)
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text("\(groupPersonas.count) " + localization.t("chats_group_members"))
                                .font(DSTypography.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    // 1v1 chat: show persona name + mood + affinity
                    VStack(spacing: 1) {
                        Text(persona.localizedName(language: localization.uiLanguage))
                            .font(DSTypography.headline)
                        HStack(spacing: 4) {
                            Text(currentMood.emoji)
                            Text(currentMood.localizedLabel(isZh: isZhUI))
                                .foregroundStyle(.secondary)
                            if currentScore > 0 {
                                Text("·").foregroundStyle(.tertiary)
                                Text(currentLevel.localizedLabel(isZh: isZhUI))
                                    .foregroundStyle(currentLevel.color)
                            }
                        }
                        .font(DSTypography.caption2)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showGift = true
                    } label: {
                        Label(localization.t("gift_title"), systemImage: "gift.fill")
                    }

                    Menu {
                        Button {
                            gameType = .rps
                            showGame = true
                        } label: {
                            Label(localization.t("game_rps"), systemImage: "hand.raised.fill")
                        }
                        Button {
                            gameType = .numberGuess
                            showGame = true
                        } label: {
                            Label(localization.t("game_number"), systemImage: "number.circle.fill")
                        }
                    } label: {
                        Label(localization.t("game_title"), systemImage: "gamecontroller.fill")
                    }

                    Divider()

                    Button {
                        withAnimation { showSearch.toggle() }
                        if !showSearch { searchQuery = "" }
                    } label: {
                        Label(localization.t("search_messages"), systemImage: "magnifyingglass")
                    }

                    ShareLink(item: exportText) {
                        Label(localization.t("chat_export"), systemImage: "square.and.arrow.up")
                    }

                    NavigationLink {
                        BackgroundPickerView(sessionId: sessionId)
                    } label: {
                        Label(localization.t("background_title"), systemImage: "photo.fill")
                    }

                    Button {
                        showMemories = true
                    } label: {
                        Label(localization.t("memories_title"), systemImage: "brain.head.profile")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Label(localization.t("chat_clear"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(localization.t("chat_clear"), isPresented: $showClearAlert) {
            Button(role: .destructive) {
                chatStore.clearMessages(in: sessionId)
                viewModel.errorMessage = nil
            } label: {
                Text(localization.t("chat_clear_confirm"))
            }
            Button(role: .cancel) {} label: {
                Text(localization.t("cancel"))
            }
        } message: {
            Text(localization.t("chat_clear_message"))
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksSheet(sessionId: sessionId) { bookmark in
                showBookmarks = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToMessageId = bookmark.messageId
                }
            }
        }
        .sheet(isPresented: $showGift) {
            GiftPanelView(sessionId: sessionId, persona: persona)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showGame) {
            switch gameType {
            case .rps:         RockPaperScissorsView()
            case .numberGuess: NumberGuessView()
            }
        }
        .sheet(isPresented: $showMemories) {
            MemoriesView(personaId: persona.id)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            if let draft = draftService.draft(for: sessionId) {
                viewModel.inputText = draft.text
                viewModel.quotedMessageId = draft.quotedMessageId
            }
        }
        .task(id: viewModel.inputText) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if viewModel.inputText.isEmpty {
                draftService.clear(for: sessionId)
            } else {
                draftService.save(
                    text: viewModel.inputText,
                    quotedMessageId: viewModel.quotedMessageId,
                    for: sessionId
                )
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(localization.t("search_placeholder"), text: $searchQuery)
                .font(DSTypography.body)
                .submitLabel(.search)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DSSpacing.sm) {
                    if messages.isEmpty {
                        emptyHint
                    }
                    ForEach(messages) { msg in
                        MessageBubble(
                            message: msg,
                            messages: allMessages,
                            persona: persona,
                            sessionId: sessionId,
                            onQuote: { quoted in viewModel.quotedMessageId = quoted.id },
                            onDelete: { msgId in chatStore.deleteMessage(id: msgId, in: sessionId) }
                        )
                        .id(msg.id)
                    }
                    if viewModel.isTyping {
                        TypingIndicator(persona: persona)
                            .id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            }
            .onChange(of: messages.count) {
                withAnimation(.spring(response: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isTyping) {
                if viewModel.isTyping {
                    withAnimation(.spring(response: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollToMessageId) { _, newId in
                if let id = newId {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                    scrollToMessageId = nil
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Empty State Hint

    private var emptyHint: some View {
        VStack(spacing: DSSpacing.md) {
            Circle()
                .fill(persona.accentColor.opacity(0.12))
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .strokeBorder(persona.accentColor.opacity(0.25), lineWidth: 1.5)
                )
                .overlay(
                    Text(String(persona.name.prefix(1)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(persona.accentColor)
                )

            VStack(spacing: DSSpacing.xxs) {
                Text(persona.localizedName(language: localization.uiLanguage))
                    .font(DSTypography.title3)
                HStack(spacing: 4) {
                    Text(currentMood.emoji)
                    Text(currentMood.localizedLabel(isZh: isZhUI))
                        .foregroundStyle(.secondary)
                }
                .font(DSTypography.caption1)
                Text(persona.localizedPersonality(language: localization.uiLanguage))
                    .font(DSTypography.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DSSpacing.xxl)

                // Affinity progress badge (shown once the user has sent at least one message)
                if currentScore > 0 {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(currentLevel.color)
                        Text(currentLevel.localizedLabel(isZh: isZhUI))
                            .foregroundStyle(currentLevel.color)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(currentScore)/100")
                            .foregroundStyle(.secondary)
                    }
                    .font(DSTypography.caption2)
                    .padding(.top, DSSpacing.xxs)
                }
            }
        }
        .padding(.vertical, DSSpacing.xxxl)
    }

    // MARK: - Export

    private var exportText: String {
        var lines = [String]()
        lines.append("Chat with \(persona.localizedName(language: localization.uiLanguage))")
        lines.append("Exported on \(Self.exportDateFormatter.string(from: Date()))")
        lines.append("")
        for msg in allMessages {
            let sender = msg.role == .user
                ? "You"
                : persona.localizedName(language: localization.uiLanguage)
            let time = Self.exportTimeFormatter.string(from: msg.timestamp)
            lines.append("[\(time)] \(sender): \(msg.content)")
        }
        return lines.joined(separator: "\n")
    }

    private static let exportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let exportTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    // MARK: - Actions

    private func send() {
        guard let session else { return }
        if session.isGroup {
            viewModel.sendGroupMessage(
                sessionId: session.id,
                groupPersonaIds: session.personaIds,
                chatStore: chatStore,
                primaryPersona: persona,
                apiConfigStore: apiConfigStore,
                localization: localization,
                affinityService: affinityService,
                draftService: draftService,
                socialService: socialService,
                memoryService: memoryService
            )
        } else {
            viewModel.sendMessage(
                sessionId: session.id,
                chatStore: chatStore,
                persona: persona,
                apiConfigStore: apiConfigStore,
                localization: localization,
                affinityService: affinityService,
                draftService: draftService,
                socialService: socialService,
                memoryService: memoryService,
                toolExecutor: ToolExecutorService.shouldUseTool(for: persona) ? toolExecutorService : nil
            )
        }
    }
}
