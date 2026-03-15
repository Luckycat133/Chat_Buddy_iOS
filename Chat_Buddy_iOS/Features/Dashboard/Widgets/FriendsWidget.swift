import SwiftUI

struct FriendsWidget: View {
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        BentoCardView(
            icon: "person.2.fill",
            title: localization.t("friends"),
            iconColor: .purple
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                // Stacked avatar row with separation rings
                HStack(spacing: -10) {
                    ForEach(PersonaStore.socialCompanions.prefix(4)) { persona in
                        Circle()
                            .fill(persona.accentColor.opacity(0.25))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Text(String(persona.name.prefix(1)))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(persona.accentColor)
                            }
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(UIColor.systemBackground), lineWidth: 1.5)
                            )
                    }

                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Text("+\(PersonaStore.socialCompanions.count - 4)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .overlay(
                            Circle()
                                .strokeBorder(Color(UIColor.systemBackground), lineWidth: 1.5)
                        )
                }

                Text("\(PersonaStore.allPersonas.count) AI")
                    .font(DSTypography.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
