import SwiftUI

struct ThemeModePickerView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        @Bindable var tm = themeManager

        Form {
            Section {
                Picker(localization.t("theme_mode"), selection: $tm.mode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Label(localization.t(mode.localizedKey), systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle(localization.t("theme_mode"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
