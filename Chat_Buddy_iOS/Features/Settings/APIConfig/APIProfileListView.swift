import SwiftUI

struct APIProfileListView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(APIConfigStore.self) private var configStore

    var body: some View {
        Form {
            if configStore.profiles.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(localization.t("no_profiles"), systemImage: "tray")
                    }
                }
            } else {
                Section {
                    ForEach(configStore.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(DSTypography.body)
                                Text(profile.config.model)
                                    .font(DSTypography.caption1)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(localization.t("load_profile")) {
                                configStore.loadProfile(profile)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .onDelete { offsets in
                        configStore.deleteProfile(at: offsets)
                    }
                }
            }
        }
        .navigationTitle(localization.t("provider_profiles"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
