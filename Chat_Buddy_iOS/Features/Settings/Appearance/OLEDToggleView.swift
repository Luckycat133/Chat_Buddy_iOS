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
                Text(localization.t("oled_mode_desc"))
            }
        }
        .navigationTitle(localization.t("oled_mode"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
