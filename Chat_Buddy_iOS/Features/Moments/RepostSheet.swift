import SwiftUI

/// Half-height sheet to repost a moment as a chat message.
struct RepostSheet: View {
    let postId: String
    @Binding var isPresented: Bool

    @Environment(MomentsStore.self) private var momentsStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    @State private var successSessionId: String? = nil

    private var post: MomentPost? { momentsStore.posts.first { $0.id == postId } }

    private var authorName: String {
        guard let p = post else { return "" }
        if p.authorId == "user-me" { return "You" }
        return PersonaStore.persona(byId: p.authorId)?.name ?? p.authorId
    }

    var body: some View {
        NavigationStack {
            Group {
                if chatStore.sessions.isEmpty {
                    ContentUnavailableView {
                        Label(localization.t("moments_select_chat"), systemImage: "bubble.left.and.bubble.right")
                    }
                } else {
                    List(chatStore.sessions) { session in
                        sessionRow(session)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(localization.t("moments_share_to_chat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("cancel")) { isPresented = false }
                }
            }
        }
    }

    // MARK: - Session Row

    private func sessionRow(_ session: ChatSession) -> some View {
        let persona = PersonaStore.persona(byId: session.personaId)
        let name = persona?.name ?? session.personaId
        let color = persona?.accentColor ?? .blue
        let didShare = successSessionId == session.id

        return Button {
            repost(to: session)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(color.opacity(0.3), lineWidth: 1))
                    .overlay(
                        Text(String(name.prefix(1)))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(color)
                    )
                Text(name)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                if didShare {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .disabled(didShare)
    }

    // MARK: - Repost Logic

    private func repost(to session: ChatSession) {
        guard let p = post else { return }
        let prefix = "[Shared Moment · \(authorName)]"
        let body = String(p.content.prefix(200))
        let fullText = "\(prefix)\n\(body)"

        let msg = ChatMessage(role: .user, content: fullText)
        chatStore.appendMessage(msg, to: session.id)

        successSessionId = session.id

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isPresented = false
        }
    }
}
