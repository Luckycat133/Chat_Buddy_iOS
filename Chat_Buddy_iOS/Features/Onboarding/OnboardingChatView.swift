import SwiftUI
import SwiftData

/// Mira onboarding per skill §"Mira onboarding":
///
///   - After auth, sync creates or returns the Mira direct conversation.
///   - UI remains an ordinary chat; Mira is never a special system bubble.
///   - The server owns the onboarding state machine; completion, step
///     advance, and resume are server decisions the UI merely reflects.
///   - Forkable breakpoint resume: leaving mid-onboarding ("Not now")
///     keeps server state; the next launch re-enters this conversation.
///   - Composer never locks; optimistic rows like the normal chat.
public struct OnboardingChatView: View {
    @EnvironmentObject private var app: CloudAppState
    @Environment(LocalizationManager.self) private var loc
    @State private var rows: [ChatRowModel] = []
    @State private var serverMessages: [RemoteMessageDTO] = []
    @State private var outboxSnapshots: [OutboxMutationSnapshot] = []
    @State private var draft: String = ""
    @State private var error: String?
    @State private var miraConversationId: String?
    @State private var onboardingConversation: ConversationRepository.ConversationListItem?
    @State private var completedOnboarding = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timeline
                Divider()
                composer
            }
            .navigationTitle(loc.t("cloud_onboarding_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("cloud_onboarding_not_now")) {
                        // Breakpoint, not exit: the server keeps onboarding
                        // state; next launch resumes the same conversation.
                        app.transition(to: .ready)
                    }
                    .accessibilityLabel(loc.t("cloud_onboarding_not_now_a11y"))
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if completedOnboarding {
                        Label(loc.t("cloud_onboarding_complete_banner"), systemImage: "checkmark.seal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.red)
                    }
                    ForEach(rows) { row in
                        OnboardingMessageBubble(message: row)
                            .id(row.id)
                    }
                }
                .padding()
            }
            .onChange(of: rows.last?.id) { _, newID in
                guard let newID else { return }
                withAnimation { proxy.scrollTo(newID, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        HStack(spacing: 8) {
            TextField(loc.t("cloud_onboarding_composer_hint"), text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .accessibilityLabel(loc.t("cloud_chat_composer_a11y"))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(loc.t("cloud_chat_send_a11y"))
        }
        .padding()
        .background(.thinMaterial)
    }

    private func load() async {
        var serverState: OnboardingStatePayload?
        do {
            let state = try await app.http.get(
                Endpoints.onboardingState,
                as: OnboardingStatePayload.self,
            )
            serverState = state
            if !OnboardingGate.shouldResumeOnboarding(
                OnboardingGate.ServerState.parse(state.state, step: state.step, awaitingUser: state.awaitingUser),
            ) {
                completedOnboarding = true
                app.transition(to: .ready)
                return
            }
            error = nil
        } catch {
            // State fetch is best-effort; conversation discovery and
            // creation below remain the source of truth the user sees.
        }
        do {
            var item = try await fetchOnboardingConversation()
            if item == nil, let serverState,
               let target = OnboardingGate.advanceTarget(serverValue: serverState.state) {
                try await ensureOnboardingConversation(state: target)
                item = try await fetchOnboardingConversation()
            }
            if let item {
                onboardingConversation = item
                miraConversationId = item.id
                serverMessages = try await app.conversations.listMessages(conversationId: item.id)
                // Onboarding rows enter the sync flow: the server may
                // not emit world_events for this conversation, so
                // `/v1/sync` alone leaves the cache-first Chats list
                // empty on a new account.
                await hydrateSyncCache()
                await refreshOutbox()
                rebuildRows()
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    /// `GET /v1/onboarding` is read-only. A fresh account returns
    /// `welcome` before any conversation exists, so the first
    /// `POST /v1/onboarding/advance` is the server operation that actually
    /// creates the Mira conversation. Re-posting the current non-complete
    /// state is idempotent when discovery raced a prior creation.
    private func ensureOnboardingConversation(state: String) async throws {
        struct Body: Codable, Sendable {
            let to: String
        }
        _ = try await app.http.send(
            Endpoints.advanceOnboarding(),
            method: "POST",
            body: Body(to: state),
            as: OnboardingStatePayload.self,
        )
    }

    private func fetchOnboardingConversation() async throws -> ConversationRepository.ConversationListItem? {
        // Read-only onboarding state does not create a conversation. If
        // `load()` has not bootstrapped it yet, discover the server row and
        // return nil so the caller can issue the first advance request.
        // Prefer the Mira direct chat, then any direct chat, then anything.
        let items = try await app.conversations.listConversations()
        if let mira = items.first(where: {
            $0.publicName?.caseInsensitiveCompare("Mira") == .orderedSame
        }) {
            return mira
        }
        if let direct = items.first(where: { $0.type == "direct" }) ?? items.first {
            return direct
        }
        // Nothing yet (e.g. initial sync failed): leave nil so send() can
        // retry discovery instead of silently dropping the message.
        return nil
    }

    /// Apply the REST-read onboarding rows to the same cache tables the
    /// sync pipeline feeds (EventApplier), and fetch counterpart actors
    /// cache-first so the direct-chat title resolves. Best-effort: a
    /// failure only delays visibility until the next sync.
    private func hydrateSyncCache() async {
        guard let summary = onboardingConversation,
              let myActorId = await app.auth.currentActorId() else { return }
        for senderId in Set(serverMessages.map(\.senderActorId)) where senderId != myActorId {
            _ = try? await app.actors.fetchActor(id: senderId)
        }
        await app.conversations.hydrateOnboardingConversation(
            summary: summary,
            messages: serverMessages,
            myActorId: myActorId,
        )
    }

    private func send() async {
        var summary = onboardingConversation
        if summary == nil {
            // Degradation path: retry discovery once so the user's first
            // message still goes out even if the conversation wasn't
            // created when the view loaded.
            do {
                summary = try await fetchOnboardingConversation()
                onboardingConversation = summary
                miraConversationId = summary?.id
            } catch {
                self.error = String(describing: error)
                return
            }
        }
        guard let id = summary?.id else {
            error = loc.t("cloud_onboarding_not_ready")
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // Optimistic send: outbox row first, then flush; the composer
        // never locks while Mira is responding.
        do {
            let key = try await app.conversations.enqueueMessage(conversationId: id, content: text)
            await refreshOutbox()
            rebuildRows()
            do {
                _ = try await app.conversations.flushOne(idempotencyKey: key)
                error = nil
            } catch {
                self.error = NSLocalizedString("cloud_chat_send_failed_notice", comment: "")
            }
        } catch {
            self.error = NSLocalizedString("cloud_chat_send_failed_notice", comment: "")
        }
        await reconcileAndCheckCompletion()
    }

    private func reconcileAndCheckCompletion() async {
        guard let id = miraConversationId else { return }
        // Cursor-based delta sync first: pull anything the server did
        // emit for this exchange (actor rows, events) before re-reading
        // the conversation.
        if let accountId = await app.auth.currentAccountId() {
            try? await app.sync.runSync(accountId: accountId)
        }
        do {
            serverMessages = try await app.conversations.listMessages(conversationId: id)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
        // Keep the sync-backed cache truthful after every exchange so the
        // Chats tab shows the onboarding session the moment onboarding
        // hands over to `.ready`.
        await hydrateSyncCache()
        // Follow the server state machine: completion is a server decision.
        if let state = try? await app.http.get(
            Endpoints.onboardingState,
            as: OnboardingStatePayload.self,
        ) {
            let parsed = OnboardingGate.ServerState.parse(
                state.state, step: state.step, awaitingUser: state.awaitingUser,
            )
            if parsed == .complete {
                completedOnboarding = true
                app.transition(to: .ready)
            }
        }
    }

    private func refreshOutbox() async {
        guard let accountId = await app.auth.currentAccountId() else {
            outboxSnapshots = []
            return
        }
        let pending = await app.outbox.pendingSnapshots(accountId: accountId)
        outboxSnapshots = miraConversationId.map { id in
            pending.filter { $0.conversationId == id }
        } ?? []
    }

    private func rebuildRows() {
        rows = ChatOutboxReducer.merge(server: serverMessages, outbox: outboxSnapshots)
    }
}

private struct OnboardingMessageBubble: View {
    let message: ChatRowModel
    @Environment(LocalizationManager.self) private var loc

    private var isHuman: Bool { message.isFromHuman }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isHuman { Spacer() }
            Text(message.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isHuman ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(
                    Text("\(isHuman ? loc.t("cloud_chat_a11y_you") : loc.t("cloud_onboarding_a11y_mira")) \(message.content)"),
                )
            if isHuman {
                switch message.status {
                case .queued, .sending:
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(loc.t("cloud_chat_status_queued"))
                case .failed, .conflict:
                    Image(systemName: "exclamationmark.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .accessibilityLabel(loc.t("cloud_chat_status_retry_a11y"))
                case .delivered:
                    EmptyView()
                }
            }
            if !isHuman { Spacer() }
        }
    }
}
