import SwiftUI

struct MomentsPlaceholderView: View {
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(localization.t("nav_moments"), systemImage: "sparkles")
            } description: {
                Text(localization.t("coming_soon"))
            }
            .navigationTitle(localization.t("nav_moments"))
        }
    }
}
