import SwiftUI

/// A single chat message bubble — trailing for user, leading for AI
struct MessageBubble: View {
    let message: ChatMessage
    let messages: [ChatMessage]
    let persona: Persona
    let sessionId: String
    let onQuote: (ChatMessage) -> Void
    let onDelete: (String) -> Void

    @Environment(AccentColorManager.self) private var accentManager
    @Environment(BookmarkService.self) private var bookmarkService
    @Environment(LocalizationManager.self) private var localization

    private var isUser: Bool { message.role == .user }
    private var isBookmarked: Bool { bookmarkService.isBookmarked(message.id) }

    /// Resolves the actual persona who sent this message (supports group chats).
    private var speakingPersona: Persona {
        if let pid = message.speakingPersonaId, let p = PersonaStore.persona(byId: pid) { return p }
        return persona
    }

    /// Resolves the quoted message from the messages array
    private var quotedMessage: ChatMessage? {
        guard let quotedId = message.quotedMessageId else { return nil }
        return messages.first { $0.id == quotedId }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            if isUser {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 2) {
                    userBubble
                    timestamp
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    aiBubble
                    timestamp
                }
                Spacer(minLength: 60)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label(localization.t("message_copy"), systemImage: "doc.on.doc")
            }

            Button {
                bookmarkService.toggleBookmark(message, sessionId: sessionId, personaId: persona.id)
            } label: {
                Label(
                    isBookmarked ? localization.t("bookmark_remove") : localization.t("bookmark_add"),
                    systemImage: isBookmarked ? "bookmark.fill" : "bookmark"
                )
            }

            Button {
                onQuote(message)
            } label: {
                Label(localization.t("message_quote"), systemImage: "arrowshape.turn.up.left")
            }

            if isUser {
                Divider()
                Button(role: .destructive) {
                    onDelete(message.id)
                } label: {
                    Label(localization.t("message_delete"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Timestamp

    private var timestamp: some View {
        Text(message.timestamp, style: .time)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, DSSpacing.xs)
    }

    // MARK: - User bubble

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
            if let quoted = quotedMessage {
                quotedPreview(for: quoted)
            }
            Text(message.content)
                .font(DSTypography.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(accentManager.currentColor, in: RoundedRectangle(cornerRadius: DSRadius.lg))
    }

    // MARK: - AI bubble

    private var aiBubble: some View {
        let sp = speakingPersona
        return HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            // Persona avatar
            Circle()
                .fill(sp.accentColor.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(sp.accentColor.opacity(0.3), lineWidth: 1))
                .overlay(
                    Text(String(sp.name.prefix(1)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(sp.accentColor)
                )

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                // In group chats show which persona is speaking
                if message.speakingPersonaId != nil {
                    Text(sp.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(sp.accentColor)
                        .padding(.leading, DSSpacing.xs)
                }
                if let quoted = quotedMessage { quotedPreview(for: quoted) }
                Text(message.content)
                    .font(DSTypography.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    // MARK: - Quoted preview (read-only, inside bubble)

    private func quotedPreview(for quoted: ChatMessage) -> some View {
        let senderName: String
        let accentColor: Color
        if quoted.role == .user {
            senderName = "You"
            accentColor = accentManager.currentColor
        } else {
            let sp = quoted.speakingPersonaId.flatMap { PersonaStore.persona(byId: $0) } ?? persona
            senderName = sp.name
            accentColor = sp.accentColor
        }
        return QuotedMessageView(senderName: senderName, content: quoted.content, accentColor: accentColor)
    }
}
