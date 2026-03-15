import SwiftUI

struct BackgroundPickerView: View {
    @Environment(BackgroundStore.self) private var backgroundStore
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.colorScheme) private var colorScheme

    var sessionId: String? = nil    // nil → global setting

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: DSSpacing.sm)]

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
}
