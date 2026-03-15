import SwiftUI

struct ConnectivityTestView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(APIConfigStore.self) private var configStore
    @State private var latency: Int?
    @State private var error: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: DSSpacing.md) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.large)
                        Text(localization.t("testing_connection"))
                    } else if let latency {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text(localization.t("connection_success", params: ["latency": "\(latency)"]))
                            .font(DSTypography.headline)
                    } else if let error {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text(localization.t("connection_failed", params: ["error": error]))
                            .font(DSTypography.footnote)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.xl)
            }

            Section {
                Button {
                    runTest()
                } label: {
                    Label(localization.t("test_connection"), systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isTesting)
            }
        }
        .navigationTitle(localization.t("test_connection"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear { runTest() }
    }

    private func runTest() {
        isTesting = true
        latency = nil
        error = nil

        Task {
            let result = await APIConfigValidator.testConnection(config: configStore.activeConfig)
            await MainActor.run {
                isTesting = false
                switch result {
                case .success(let ms):
                    latency = ms
                case .failure(let err):
                    error = err.localizedDescription
                }
            }
        }
    }
}
