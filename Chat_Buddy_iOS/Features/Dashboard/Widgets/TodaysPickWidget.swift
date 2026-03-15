import SwiftUI

struct TodaysPickWidget: View {
    @Environment(LocalizationManager.self) private var localization
    let persona: Persona

    var body: some View {
        GlassCard(cornerRadius: DSRadius.xl) {
            HStack(spacing: DSSpacing.md) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(persona.accentColor.opacity(0.18))
                        .frame(width: 60, height: 60)
                    Circle()
                        .strokeBorder(persona.accentColor.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 60, height: 60)
                    Text(String(persona.name.prefix(1)))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(persona.accentColor)
                }

                // Info
                VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                    HStack(spacing: DSSpacing.xxxs) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text(localization.t("todays_pick"))
                            .font(DSTypography.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }

                    Text(persona.localizedName(language: localization.resolvedLanguage))
                        .font(DSTypography.title3)

                    Text(persona.localizedPersonality(language: localization.resolvedLanguage))
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // CTA arrow
                VStack(spacing: DSSpacing.xxxs) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(persona.accentColor)
                    Text(localization.t("tap_to_chat"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
