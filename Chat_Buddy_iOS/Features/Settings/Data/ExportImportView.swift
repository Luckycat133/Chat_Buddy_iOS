import SwiftUI
import UniformTypeIdentifiers

struct ExportImportView: View {
    @Environment(AppState.self) private var appState
    @Environment(LocalizationManager.self) private var localization
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AccentColorManager.self) private var accentColorManager
    @Environment(APIConfigStore.self) private var configStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(AffinityService.self) private var affinityService
    @Environment(BookmarkService.self) private var bookmarkService
    @Environment(DraftService.self) private var draftService
    @Environment(MomentsStore.self) private var momentsStore
    @Environment(BackgroundStore.self) private var backgroundStore
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(SocialService.self) private var socialService
    @Environment(FriendService.self) private var friendService
    @Environment(MemoryService.self) private var memoryService

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: BackupDocument?
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var includeSensitiveData = false
    @State private var showSensitiveDataWarning = false

    var body: some View {
        Form {
            // Export
            Section {
                Toggle(isOn: $includeSensitiveData) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.t("export_include_sensitive"))
                        Text(localization.t("export_include_sensitive_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: includeSensitiveData) { _, newValue in
                    if newValue {
                        showSensitiveDataWarning = true
                    }
                }
                .alert(localization.t("warning"), isPresented: $showSensitiveDataWarning) {
                    Button(localization.t("cancel"), role: .cancel) {
                        includeSensitiveData = false
                    }
                    Button(localization.t("confirm")) {}
                } message: {
                    Text(localization.t("export_sensitive_warning"))
                }
                
                Button {
                    exportData()
                } label: {
                    SettingRow(
                        icon: "square.and.arrow.up.fill",
                        iconColor: .blue,
                        title: localization.t("export_data_title"),
                        subtitle: localization.t("export_data_desc")
                    )
                }
                .tint(.primary)
            }

            // Import
            Section {
                Button {
                    showImporter = true
                } label: {
                    SettingRow(
                        icon: "square.and.arrow.down.fill",
                        iconColor: .green,
                        title: localization.t("import_data"),
                        subtitle: localization.t("import_data_desc")
                    )
                }
                .tint(.primary)
            }
        }
        .navigationTitle(localization.t("export_data"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "chat-buddy-backup-\(formattedDate).json"
        ) { result in
            switch result {
            case .success:
                alertMessage = localization.t("export_success")
                showAlert = true
            case .failure(let error):
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .alert(localization.t("success"), isPresented: $showAlert) {
            Button(localization.t("done")) {}
        } message: {
            if let msg = alertMessage {
                Text(msg)
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func exportData() {
        do {
            let data = try DataExporter.exportToData(configStore: configStore, includeSensitiveData: includeSensitiveData)
            exportDocument = BackupDocument(data: data)
            showExporter = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let count = try DataImporter.importBackup(
                    from: data,
                    configStore: configStore,
                    localization: localization,
                    themeManager: themeManager,
                    accentColorManager: accentColorManager,
                    appState: appState,
                    stores: [chatStore, affinityService, bookmarkService, draftService, momentsStore, backgroundStore, userProfileStore, socialService, friendService, memoryService]
                )
                alertMessage = localization.t("import_success", params: ["count": "\(count)"])
                showAlert = true
            } catch {
                alertMessage = localization.t("import_failed", params: ["error": error.localizedDescription])
                showAlert = true
            }

        case .failure(let error):
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}
