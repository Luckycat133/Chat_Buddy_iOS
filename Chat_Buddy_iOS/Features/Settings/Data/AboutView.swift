import SwiftUI

struct AboutView: View {
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        Form {
            // App info
            Section {
                VStack(spacing: DSSpacing.md) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)

                    Text(AppConstants.appName)
                        .font(DSTypography.title1)

                    Text(localization.t("about_tagline"))
                        .font(DSTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.lg)
            }

            Section {
                LabeledContent(localization.t("version"), value: AppConstants.fullVersion)
                LabeledContent(localization.t("developer"), value: AppConstants.developer)
            }

            Section(localization.t("about")) {
                Text("Chat Buddy is a feature-rich AI chat companion with multiple personalities, bilingual support, and social features.")
                    .font(DSTypography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(localization.t("about"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
