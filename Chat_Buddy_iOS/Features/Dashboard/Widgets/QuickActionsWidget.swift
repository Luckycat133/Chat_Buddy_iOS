import SwiftUI

struct QuickActionsWidget: View {
    @Environment(LocalizationManager.self) private var localization

    /// Called when the user taps "New Chat". Typically switches the root tab to Chats.
    var onNewChat: () -> Void = {}
    /// Called when the user taps "Friends". Typically switches to Moments/Social.
    var onFriends: () -> Void = {}

    var body: some View {
        BentoCardView(
            icon: "bolt.fill",
            title: localization.t("quick_actions"),
            iconColor: .orange
        ) {
            VStack(spacing: DSSpacing.xs) {
                Button(action: onNewChat) {
                    actionRow(icon: "plus.bubble.fill", label: localization.t("chats_new_chat"))
                }
                .buttonStyle(.plain)

                Button(action: onFriends) {
                    actionRow(icon: "person.2.fill", label: localization.t("friends"))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionRow(icon: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: DSIconSize.sm))
                .foregroundStyle(.tint)
            Text(label)
                .font(DSTypography.caption1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
