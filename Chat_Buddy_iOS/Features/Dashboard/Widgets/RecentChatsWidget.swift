import SwiftUI

struct RecentChatsWidget: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(ChatStore.self) private var chatStore

    /// Up to 3 most recently updated sessions that contain at least one message.
    private var recentSessions: [ChatSession] {
        Array(chatStore.sessions.filter { !$0.displayMessages.isEmpty }.prefix(3))
    }

    var body: some View {
        BentoCardView(
            icon: "bubble.left.and.bubble.right.fill",
            title: localization.t("recent_chats"),
            iconColor: .blue
        ) {
            if recentSessions.isEmpty {
                Text(localization.t("chats_empty_desc"))
                    .font(DSTypography.caption2)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(recentSessions) { session in
                        recentRow(for: session)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentRow(for session: ChatSession) -> some View {
        let persona = PersonaStore.allPersonas.first { $0.id == session.personaId }
        let name    = persona?.localizedName(language: localization.uiLanguage) ?? session.personaId
        let color   = persona?.accentColor ?? Color.accentColor
        let preview = session.lastMessage?.content ?? ""

        HStack(spacing: DSSpacing.xs) {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(String(name.prefix(1)))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(DSTypography.caption1)
                    .lineLimit(1)
                if !preview.isEmpty {
                    Text(preview)
                        .font(DSTypography.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
