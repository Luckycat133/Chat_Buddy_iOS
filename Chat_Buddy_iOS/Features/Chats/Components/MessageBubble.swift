import SwiftUI

/// A single chat message bubble — trailing for user, leading for AI
struct MessageBubble: View {
    let message: ChatMessage
    let messages: [ChatMessage]
    let polls: [ChatPoll]
    let persona: Persona
    let sessionId: String
    let onQuote: (ChatMessage) -> Void
    let onDelete: (String) -> Void
    let onForward: (ChatMessage) -> Void
    let onVotePoll: (String, String) -> Void

    @Environment(AccentColorManager.self) private var accentManager
    @Environment(BookmarkService.self) private var bookmarkService
    @Environment(LocalizationManager.self) private var localization

    private var isUser: Bool { message.role == .user }
    private var isTool: Bool { message.role == .tool }
    private var isBookmarked: Bool { bookmarkService.isBookmarked(message.id) }
    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private enum ParsedType {
        case plain
        case forwarded(String)
        case redPacket(amount: String, blessing: String)
        case game(String)
        case poll(ChatPoll)
    }

    private var parsedType: ParsedType {
        if message.content.hasPrefix("[FORWARDED:"), let body = forwardedBody(from: message.content) {
            return .forwarded(body)
        }

        if message.content.hasPrefix("[RED_PACKET:"),
           let payload = payload(from: message.content, prefix: "[RED_PACKET:") {
            let parts = payload.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                return .redPacket(amount: String(parts[0]), blessing: String(parts[1]))
            }
        }

        if message.content.hasPrefix("[GAME:"),
           let payload = payload(from: message.content, prefix: "[GAME:") {
            return .game(payload)
        }

        if message.content.hasPrefix("[POLL:"),
           let payload = payload(from: message.content, prefix: "[POLL:"),
           let poll = polls.first(where: { $0.id == payload }) {
            return .poll(poll)
        }

        return .plain
    }

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
            } else if isTool {
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 2) {
                    toolBubble
                    timestamp
                }
                Spacer(minLength: 24)
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
#if canImport(UIKit)
                UIPasteboard.general.string = message.content
#else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
#endif
            } label: {
                Label(localization.t("message_copy"), systemImage: "doc.on.doc")
            }

            if !isTool {
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

                Button {
                    onForward(message)
                } label: {
                    Label(isZh ? "转发" : "Forward", systemImage: "arrowshape.turn.up.right")
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
            messageContentView(isUserBubble: true)
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
                messageContentView(isUserBubble: false)
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

    // MARK: - Tool bubble

    private var toolBubble: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(localization.t("chat_tool_result"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(message.content)
                .font(DSTypography.footnote)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .strokeBorder(.orange.opacity(0.25), lineWidth: 1)
        )
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

    // MARK: - Message Content Parsing

    @ViewBuilder
    private func messageContentView(isUserBubble: Bool) -> some View {
        switch parsedType {
        case .plain:
            Text(message.content)
                .font(DSTypography.body)
                .foregroundStyle(isUserBubble ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .textSelection(.enabled)

        case .forwarded(let body):
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Label(isZh ? "转发消息" : "Forwarded", systemImage: "arrowshape.turn.up.right")
                    .font(DSTypography.caption2.weight(.semibold))
                    .foregroundStyle(isUserBubble ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                Text(body)
                    .font(DSTypography.body)
                    .foregroundStyle(isUserBubble ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }

        case .redPacket(let amount, let blessing):
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "yensign.circle.fill")
                    .foregroundStyle(isUserBubble ? AnyShapeStyle(.white) : AnyShapeStyle(.orange))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isZh ? "红包 ¥\(amount)" : "Red Packet ¥\(amount)")
                        .font(DSTypography.footnote.weight(.semibold))
                        .foregroundStyle(isUserBubble ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    Text(blessing)
                        .font(DSTypography.caption1)
                        .foregroundStyle(isUserBubble ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                }
            }

        case .game(let gamePayload):
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "gamecontroller.fill")
                Text(gamePayload)
                    .lineLimit(3)
            }
            .font(DSTypography.footnote)
            .foregroundStyle(isUserBubble ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))

        case .poll(let poll):
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(poll.question)
                    .font(DSTypography.footnote.weight(.semibold))
                    .foregroundStyle(isUserBubble ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(2)

                ForEach(poll.options) { option in
                    let totalVotes = max(1, poll.options.reduce(0) { $0 + $1.votes.count })
                    let voteRate = Double(option.votes.count) / Double(totalVotes)
                    let voted = option.votes.contains("user-me")

                    Button {
                        guard !poll.isExpired else { return }
                        onVotePoll(poll.id, option.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(option.text)
                                    .font(DSTypography.caption1)
                                    .foregroundStyle(isUserBubble ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(option.votes.count)")
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(isUserBubble ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                                if voted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(isUserBubble ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
                                }
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill((isUserBubble ? Color.white : Color.secondary).opacity(0.18))
                                    Capsule().fill((isUserBubble ? Color.white : Color.accentColor).opacity(0.45))
                                        .frame(width: proxy.size.width * voteRate)
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 6)
                        .background((isUserBubble ? Color.white : Color.secondary).opacity(voted ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: DSRadius.sm))
                    }
                    .buttonStyle(.plain)
                    .disabled(poll.isExpired)
                }

                if poll.isExpired {
                    Text(isZh ? "投票已结束" : "Poll closed")
                        .font(DSTypography.caption2)
                        .foregroundStyle(isUserBubble ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                }
            }
        }
    }

    private func payload(from content: String, prefix: String) -> String? {
        guard content.hasPrefix(prefix), content.hasSuffix("]") else { return nil }
        let start = content.index(content.startIndex, offsetBy: prefix.count)
        let end = content.index(before: content.endIndex)
        guard start <= end else { return nil }
        return String(content[start..<end])
    }

    private func forwardedBody(from content: String) -> String? {
        let lines = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2 else { return nil }
        return String(lines[1])
    }
}
