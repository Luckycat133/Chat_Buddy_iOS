import SwiftUI

struct SettingsView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(AppState.self) private var appState
    @Environment(SocialService.self) private var socialService

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Profile
                Section(localization.t("settings_profile")) {
                    NavigationLink {
                        UserProfileView()
                    } label: {
                        SettingRow(
                            icon: "person.crop.circle.fill",
                            iconColor: .blue,
                            title: localization.t("profile_title")
                        )
                    }
                }

                // MARK: - Social
                Section(localization.t("settings_social")) {
                    NavigationLink {
                        DailyCheckInView()
                    } label: {
                        SettingRow(
                            icon: "calendar.badge.checkmark",
                            iconColor: .orange,
                            title: localization.t("checkin_title"),
                            subtitle: socialService.canCheckInToday ? nil : localization.t("checkin_done")
                        )
                    }

                    NavigationLink {
                        AchievementsView()
                    } label: {
                        SettingRow(
                            icon: "trophy.fill",
                            iconColor: .yellow,
                            title: localization.t("achievements_title"),
                            subtitle: "\(socialService.points) \(localization.t("achievements_points"))"
                        )
                    }
                }

                // MARK: - Appearance
                Section(localization.t("appearance")) {
                    NavigationLink {
                        ThemeModePickerView()
                    } label: {
                        SettingRow(
                            icon: "paintpalette.fill",
                            iconColor: .purple,
                            title: localization.t("theme_mode")
                        )
                    }

                    NavigationLink {
                        OLEDToggleView()
                    } label: {
                        SettingRow(
                            icon: "moon.circle.fill",
                            iconColor: .indigo,
                            title: localization.t("oled_mode")
                        )
                    }

                    NavigationLink {
                        AccentColorPickerView()
                    } label: {
                        SettingRow(
                            icon: "paintbrush.fill",
                            iconColor: .orange,
                            title: localization.t("accent_color")
                        )
                    }

                    NavigationLink {
                        AnimationIntensityView()
                    } label: {
                        SettingRow(
                            icon: "wand.and.stars",
                            iconColor: .cyan,
                            title: localization.t("animation_intensity")
                        )
                    }

                    NavigationLink {
                        BackgroundPickerView()
                    } label: {
                        SettingRow(
                            icon: "photo.fill",
                            iconColor: .teal,
                            title: localization.t("background_title")
                        )
                    }
                }

                // MARK: - Language
                Section(localization.t("language")) {
                    NavigationLink {
                        LanguagePickerView()
                    } label: {
                        SettingRow(
                            icon: "globe",
                            iconColor: .blue,
                            title: localization.t("interface_language")
                        )
                    }

                    NavigationLink {
                        AILanguagePickerView()
                    } label: {
                        SettingRow(
                            icon: "text.bubble.fill",
                            iconColor: .teal,
                            title: localization.t("ai_language")
                        )
                    }
                }

                // MARK: - API Configuration
                Section(localization.t("api_config")) {
                    NavigationLink {
                        APIConfigView()
                    } label: {
                        SettingRow(
                            icon: "server.rack",
                            iconColor: .green,
                            title: localization.t("api_config"),
                            subtitle: localization.t("api_config_desc")
                        )
                    }

                    NavigationLink {
                        APIProfileListView()
                    } label: {
                        SettingRow(
                            icon: "list.bullet.rectangle.fill",
                            iconColor: .mint,
                            title: localization.t("provider_profiles")
                        )
                    }
                }

                // MARK: - Data
                Section(localization.t("data")) {
                    NavigationLink {
                        ExportImportView()
                    } label: {
                        SettingRow(
                            icon: "arrow.up.arrow.down.circle.fill",
                            iconColor: .brown,
                            title: localization.t("export_data")
                        )
                    }
                }

                // MARK: - About
                Section(localization.t("about")) {
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingRow(
                            icon: "info.circle.fill",
                            iconColor: .gray,
                            title: localization.t("about"),
                            subtitle: localization.t("about_tagline")
                        )
                    }

                    Button {
                        appState.resetOnboarding()
                    } label: {
                        SettingRow(
                            icon: "arrow.counterclockwise.circle.fill",
                            iconColor: .secondary,
                            title: localization.t("reset_tutorial"),
                            subtitle: localization.t("reset_tutorial_desc")
                        )
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle(localization.t("settings_title"))
        }
    }
}
