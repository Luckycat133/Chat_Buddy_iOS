import SwiftUI

struct OLEDToggleView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        @Bindable var tm = themeManager

        Form {
            Section {
                Toggle(localization.t("oled_mode"), isOn: $tm.oledEnabled)
            } footer: {
                Text("Uses pure black backgrounds in dark mode to save battery on OLED screens.")
            }
        }
        .navigationTitle(localization.t("oled_mode"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
