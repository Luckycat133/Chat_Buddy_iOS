import SwiftUI

struct LanguagePickerView: View {
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        @Bindable var lm = localization

        Form {
            Section {
                Picker(localization.t("interface_language"), selection: $lm.uiLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName)
                            .tag(lang)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle(localization.t("interface_language"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
