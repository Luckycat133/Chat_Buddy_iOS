import SwiftUI

struct SettingsView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(AppState.self) private var appState
    @Environment(SocialService.self) private var socialService

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

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

                    NavigationLink {
                        FriendsView()
                    } label: {
                        SettingRow(
                            icon: "person.2.fill",
                            iconColor: .purple,
                            title: localization.t("friends")
                        )
                    }

                    NavigationLink {
                        LeaderboardView()
                    } label: {
                        SettingRow(
                            icon: "chart.bar.fill",
                            iconColor: .pink,
                            title: isZh ? "排行榜" : "Leaderboard"
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

                // MARK: - Advanced Tools
                Section(isZh ? "高级工具" : "Advanced Tools") {
                    NavigationLink {
                        AgentsView()
                    } label: {
                        SettingRow(
                            icon: "sparkles",
                            iconColor: .indigo,
                            title: localization.t("ai_agents")
                        )
                    }

                    NavigationLink {
                        GlobalMessageSearchView()
                    } label: {
                        SettingRow(
                            icon: "magnifyingglass",
                            iconColor: .brown,
                            title: isZh ? "全局搜索" : "Global Search"
                        )
                    }

                    NavigationLink {
                        KnowledgeBaseView()
                    } label: {
                        SettingRow(
                            icon: "books.vertical.fill",
                            iconColor: .green,
                            title: isZh ? "知识库" : "Knowledge Base"
                        )
                    }

                    NavigationLink {
                        ModelSwitcherView()
                    } label: {
                        SettingRow(
                            icon: "cpu.fill",
                            iconColor: .blue,
                            title: isZh ? "模型切换" : "Model Switcher"
                        )
                    }

                    NavigationLink {
                        KnowledgeGraphView()
                    } label: {
                        SettingRow(
                            icon: "point.3.connected.trianglepath.dotted",
                            iconColor: .teal,
                            title: isZh ? "知识图谱" : "Knowledge Graph"
                        )
                    }

                    NavigationLink {
                        LearningReportView()
                    } label: {
                        SettingRow(
                            icon: "graduationcap.fill",
                            iconColor: .orange,
                            title: isZh ? "学习报告" : "Learning Report"
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

                    NavigationLink {
                        HelpView()
                    } label: {
                        SettingRow(
                            icon: "questionmark.circle.fill",
                            iconColor: .teal,
                            title: isZh ? "帮助" : "Help"
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
