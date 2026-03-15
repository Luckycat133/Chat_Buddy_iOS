import SwiftUI

struct AILanguagePickerView: View {
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        @Bindable var lm = localization

        Form {
            Section {
                Picker(localization.t("ai_language"), selection: $lm.aiLanguage) {
                    ForEach(AILanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName)
                            .tag(lang)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(localization.t("ai_language_desc"))
            }
        }
        .navigationTitle(localization.t("ai_language"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
