import SwiftUI

struct AnimationIntensityView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        @Bindable var tm = themeManager

        Form {
            Section {
                Picker(localization.t("animation_intensity"), selection: $tm.animationIntensity) {
                    ForEach(AnimationIntensity.allCases, id: \.self) { intensity in
                        Text(localization.t(intensity.localizedKey))
                            .tag(intensity)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle(localization.t("animation_intensity"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
