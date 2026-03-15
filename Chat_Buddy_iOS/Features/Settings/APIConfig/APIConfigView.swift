import SwiftUI

struct APIConfigView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(APIConfigStore.self) private var configStore
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult {
        case success(Int)
        case failure(String)
    }

    var body: some View {
        @Bindable var store = configStore

        Form {
            Section {
                LabeledContent(localization.t("api_base_url")) {
                    TextField("https://api.openai.com/v1", text: $store.activeConfig.baseURL)
#if os(iOS)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
#endif
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent(localization.t("api_key")) {
                    SecureField("sk-...", text: $store.activeConfig.apiKey)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent(localization.t("model_name")) {
                    TextField("deepseek-chat", text: $store.activeConfig.model)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack {
                        Text(localization.t("temperature"))
                        Spacer()
                        Text(String(format: "%.1f", store.activeConfig.temperature))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.activeConfig.temperature, in: 0...2, step: 0.1)
                }

                LabeledContent(localization.t("timeout")) {
                    TextField("60", value: $store.activeConfig.timeout, format: .number)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent(localization.t("max_retries")) {
                    TextField("3", value: $store.activeConfig.maxRetries, format: .number)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text(localization.t("temperature_desc"))
            }

            // Test connection
            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                            Text(localization.t("testing_connection"))
                        } else {
                            Image(systemName: "bolt.fill")
                            Text(localization.t("test_connection"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isTesting || !configStore.activeConfig.isValid)

                if let testResult {
                    switch testResult {
                    case .success(let latency):
                        Label(
                            localization.t("connection_success", params: ["latency": "\(latency)"]),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)

                    case .failure(let error):
                        Label(
                            localization.t("connection_failed", params: ["error": error]),
                            systemImage: "xmark.circle.fill"
                        )
                        .foregroundStyle(.red)
                        .font(DSTypography.footnote)
                    }
                }
            }

            // Save as profile
            Section {
                NavigationLink(localization.t("save_as_profile")) {
                    SaveProfileView()
                }
            }
        }
        .navigationTitle(localization.t("api_config"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let result = await APIConfigValidator.testConnection(config: configStore.activeConfig)
            await MainActor.run {
                isTesting = false
                switch result {
                case .success(let latency):
                    testResult = .success(latency)
                case .failure(let error):
                    testResult = .failure(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Save Profile Sub-view

private struct SaveProfileView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(APIConfigStore.self) private var configStore
    @Environment(\.dismiss) private var dismiss
    @State private var profileName = ""

    var body: some View {
        Form {
            Section {
                TextField(localization.t("profile_name"), text: $profileName)
            }

            Section {
                Button(localization.t("save")) {
                    guard !profileName.isEmpty else { return }
                    configStore.saveAsProfile(name: profileName)
                    dismiss()
                }
                .disabled(profileName.isEmpty)
            }
        }
        .navigationTitle(localization.t("save_as_profile"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
