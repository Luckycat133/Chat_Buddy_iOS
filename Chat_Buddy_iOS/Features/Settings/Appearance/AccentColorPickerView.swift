import SwiftUI

struct AccentColorPickerView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(AccentColorManager.self) private var accentManager
    @State private var customColor: Color = .blue

    var body: some View {
        Form {
            // Preset colors
            Section(localization.t("accent_color")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: 5), spacing: DSSpacing.md) {
                    ForEach(AccentPreset.presets) { preset in
                        Button {
                            accentManager.selectPreset(preset)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 44, height: 44)

                                if accentManager.selectedPresetId == preset.id && !accentManager.isCustom {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .accessibilityLabel(localization.t(preset.localizedKey))
                    }
                }
                .padding(.vertical, DSSpacing.xs)
            }

            // Custom color
            Section(localization.t("accent_custom")) {
                ColorPicker(localization.t("accent_custom"), selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, newValue in
                        accentManager.setCustomColor(newValue)
                    }
            }

            // Reset
            Section {
                Button(localization.t("accent_reset")) {
                    accentManager.reset()
                }
            }
        }
        .navigationTitle(localization.t("accent_color"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            if let hex = accentManager.customColorHex {
                customColor = Color(hex: hex)
            }
        }
    }
}
