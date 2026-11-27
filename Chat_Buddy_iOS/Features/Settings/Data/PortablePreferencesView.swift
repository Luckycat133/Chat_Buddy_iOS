import SwiftUI
import UniformTypeIdentifiers

/// A local, preferences-only transfer. The cloud route deliberately does not
/// expose legacy full backups, provider credentials, or account data here.
struct PortablePreferencesView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(ThemeManager.self) private var theme

    @State private var document: BackupDocument?
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var status: String?
    @State private var showStatus = false

    var body: some View {
        Form {
            Section {
                Button(label("导出跨端偏好", "Export portable preferences"), action: exportPreferences)
                Button(label("导入跨端偏好", "Import portable preferences")) {
                    showImporter = true
                }
            } footer: {
                Text(label("仅转移语言和外观，不含聊天、账户数据或凭据。",
                           "Transfers language and appearance only. Chats, account data, and credentials are excluded."))
            }
        }
        .navigationTitle(label("跨端语言与外观", "Portable language and appearance"))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], onCompletion: importPreferences)
        .fileExporter(isPresented: $showExporter, document: document, contentType: .json,
                      defaultFilename: "chat-buddy-portable-preferences.json") { result in
            if case .failure(let error) = result {
                report(error.localizedDescription)
            }
        }
        .alert(label("跨端偏好", "Portable preferences"), isPresented: $showStatus) {
            Button(localization.t("done")) {}
        } message: {
            Text(status ?? "")
        }
    }

    private func exportPreferences() {
        do {
            document = BackupDocument(data: try JSONEncoder().encode(
                PortablePreferences(localization: localization, theme: theme)
            ))
            showExporter = true
        } catch {
            report(error.localizedDescription)
        }
    }

    private func importPreferences(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            guard size <= 16_384 else {
                report(label("偏好文件过大。", "The preferences file is too large."))
                return
            }
            try handle.seek(toOffset: 0)
            let data = try handle.read(upToCount: 16_385) ?? Data()
            guard data.count <= 16_384,
                  let preferences = try PortablePreferences.decodeIfPresent(data) else {
                report(label("请选择跨端偏好文件。", "Select a portable preferences file."))
                return
            }
            preferences.apply(localization: localization, theme: theme)
            report(label("语言和外观已更新。", "Language and appearance updated."))
        } catch {
            report(error.localizedDescription)
        }
    }

    private func label(_ chinese: String, _ english: String) -> String {
        localization.uiLanguage.resolved == .zh ? chinese : english
    }

    private func report(_ message: String) {
        status = message
        showStatus = true
    }
}
