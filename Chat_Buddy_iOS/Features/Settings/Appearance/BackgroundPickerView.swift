import SwiftUI

struct BackgroundPickerView: View {
    @Environment(BackgroundStore.self) private var backgroundStore
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.colorScheme) private var colorScheme

    var sessionId: String? = nil    // nil → global setting

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: DSSpacing.sm)]
    private let animationColumns = [GridItem(.adaptive(minimum: 110), spacing: DSSpacing.sm)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if sessionId != nil {
                    resetRow
                }

                LazyVGrid(columns: columns, spacing: DSSpacing.sm) {
                    ForEach(ChatBackgroundPreset.presets) { preset in
                        presetCard(preset)
                    }
                }
                .padding(.horizontal, DSSpacing.md)

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text(localization.t("bg_animated_title"))
                        .font(DSTypography.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DSSpacing.md)

                    LazyVGrid(columns: animationColumns, spacing: DSSpacing.sm) {
                        ForEach(AnimatedBackground.allCases, id: \.self) { animation in
                            animationCard(animation)
                        }
                    }
                    .padding(.horizontal, DSSpacing.md)
                }
            }
            .padding(.vertical, DSSpacing.md)
        }
        .navigationTitle(localization.t("background_title"))
    }

    // MARK: - Subviews

    @ViewBuilder
    private func presetCard(_ preset: ChatBackgroundPreset) -> some View {
        let isSelected = isCurrentlySelected(preset)

        Button {
            if let sid = sessionId {
                backgroundStore.setChat(sessionId: sid, presetId: preset.id)
            } else {
                backgroundStore.setGlobal(presetId: preset.id)
            }
        } label: {
            VStack(spacing: DSSpacing.xs) {
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(presetFill(preset))
                    .frame(height: 70)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.md)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(6)
                        }
                    }

                Text(isZh ? preset.nameZh : preset.name)
                    .font(DSTypography.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var resetRow: some View {
        Button(role: .destructive) {
            if let sid = sessionId {
                backgroundStore.clearChat(sessionId: sid)
            }
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text(localization.t("background_reset"))
            }
            .font(DSTypography.footnote)
        }
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Helpers

    private func isCurrentlySelected(_ preset: ChatBackgroundPreset) -> Bool {
        if let sid = sessionId {
            let resolved = backgroundStore.resolvedPreset(for: sid)
            return resolved.id == preset.id
        }
        return backgroundStore.globalPresetId == preset.id
    }

    private func isCurrentAnimation(_ animation: AnimatedBackground) -> Bool {
        if let sid = sessionId {
            return backgroundStore.resolvedAnimation(for: sid) == animation
        }
        return backgroundStore.globalAnimation == animation
    }

    private func presetFill(_ preset: ChatBackgroundPreset) -> AnyShapeStyle {
        if preset.isDefault {
            return AnyShapeStyle(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.93))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color(hex: preset.startHex), Color(hex: preset.endHex)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private func animationCard(_ animation: AnimatedBackground) -> some View {
        let isSelected = isCurrentAnimation(animation)
        Button {
            if let sid = sessionId {
                backgroundStore.setChatAnimation(sessionId: sid, animation: animation)
            } else {
                backgroundStore.setGlobalAnimation(animation)
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                Text(localization.t(animation.localizationKey))
                    .font(DSTypography.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: DSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
