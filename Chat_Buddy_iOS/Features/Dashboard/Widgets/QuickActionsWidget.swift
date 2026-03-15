import SwiftUI

struct QuickActionsWidget: View {
    @Environment(LocalizationManager.self) private var localization

    /// Called when the user taps "New Chat". Typically switches the root tab to Chats.
    var onNewChat: () -> Void = {}

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

                // Friends — placeholder until Moments/T08 lands
                actionRow(icon: "person.2.fill", label: localization.t("friends"))
                    .foregroundStyle(.secondary)
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
