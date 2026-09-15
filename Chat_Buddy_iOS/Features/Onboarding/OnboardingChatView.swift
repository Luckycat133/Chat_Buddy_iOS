import SwiftUI
import SwiftData

/// Mira onboarding view per skill §"Mira onboarding":
///   - After auth, sync creates or returns the Mira direct conversation.
///   - Route into chat; show actual unread Mira message.
///   - Conversation proceeds through the server onboarding state.
///   - UI remains ordinary chat; Mira is not a special system bubble.
///   - Permission prompts only when context makes them useful.
///   - Once complete, subsequent launches go to Chats.
public struct OnboardingChatView: View {
    @EnvironmentObject private var app: CloudAppState
    @State private var messages: [RemoteMessageDTO] = []
    @State private var draft: String = ""
    @State private var sending = false
    @State private var error: String?
    @State private var miraConversationId: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timeline
                Divider()
                composer
            }
            .navigationTitle("Mira")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        app.transition(to: .ready)
                    }
                    .accessibilityLabel("Skip onboarding")
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let error {
                    Label(error, systemImage: "exclamationmark.bubble")
                        .foregroundStyle(.red)
                }
                ForEach(messages, id: \.id) { message in
                    OnboardingMessageBubble(message: message)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Tell Mira what kind of company you'd like…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(sending)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            .accessibilityLabel("Send")
        }
        .padding()
        .background(.thinMaterial)
    }

    private func load() async {
        do {
            // First, ensure onboarding conversation exists.
            let onboarding = try await fetchOnboardingConversation()
            miraConversationId = onboarding
            if let id = onboarding {
                messages = try await app.conversations.listMessages(conversationId: id)
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func fetchOnboardingConversation() async throws -> String? {
        let onboarding = try await app.http.get(Endpoints.onboardingState, as: OnboardingStateResponse.self)
        if onboarding.state == "complete" {
            app.transition(to: .ready)
            return nil
        }
        // The server creates the Mira conversation during initial sync;
        // discover it from the conversation list. Prefer the Mira direct
        // chat, then any direct chat, then anything at all.
        let items = try await app.conversations.listConversations()
        if let mira = items.first(where: {
            $0.publicName?.caseInsensitiveCompare("Mira") == .orderedSame
        }) {
            return mira.id
        }
        if let direct = items.first(where: { $0.type == "direct" }) ?? items.first {
            return direct.id
        }
        // Nothing yet (e.g. initial sync failed): leave nil so send() can
        // retry discovery instead of silently dropping the message.
        return nil
    }

    private func send() async {
        var id = miraConversationId
        if id == nil {
            // Degradation path: retry discovery once so the user's first
            // message still goes out even if the conversation wasn't
            // created when the view loaded.
            do {
                id = try await fetchOnboardingConversation()
                miraConversationId = id
            } catch {
                self.error = String(describing: error)
                return
            }
        }
        guard let id else {
            error = "Mira's conversation isn't ready yet — try again in a moment."
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            _ = try await app.conversations.sendMessage(conversationId: id, content: text)
            draft = ""
            messages = try await app.conversations.listMessages(conversationId: id)
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct OnboardingMessageBubble: View {
    let message: RemoteMessageDTO

    // Shared with CloudChatView (see `RemoteMessageDTO.isFromHuman`).
    private var isHuman: Bool { message.isFromHuman }

    var body: some View {
        // Human messages hug the trailing (right) edge: leading Spacer.
        HStack {
            if isHuman { Spacer() }
            Text(message.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isHuman ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(Text("\(isHuman ? "You" : "Mira") said \(message.content)"))
            if !isHuman { Spacer() }
        }
    }
}

private struct OnboardingStateResponse: Codable {
    let state: String
    let facts: [String: String]?
}