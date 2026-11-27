import SwiftUI
import UniformTypeIdentifiers

/// Local read-only recovery, deliberately separate from account and legacy
/// imports. The selected file remains unchanged in Files.
struct WebV2ChatArchiveView: View {
    @Environment(LocalizationManager.self) private var localization
    @State private var archive: WebV2ChatArchive?
    @State private var error: String?
    @State private var pickArchive = false

    var body: some View {
        List {
            Section {
                Button(label("选择 Web v2 备份", "Open Web v2 backup")) {
                    pickArchive = true
                }
            } footer: {
                Text(label("仅在此查看本地聊天文本。不会上传、写入云端聊天或改动原文件；请保留原文件以供恢复其他内容。",
                           "Read local chat text here. Nothing is uploaded, added to cloud chats, or changed in the original file. Keep the original for everything else."))
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if let archive {
                Section(label("恢复的聊天", "Recovered chats")) {
                    if archive.threads.isEmpty {
                        Text(label("备份中没有聊天。", "No chats in this backup."))
                    }
                    ForEach(archive.threads) { thread in
                        NavigationLink(thread.name) {
                            List(thread.messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.senderID).font(.caption.weight(.semibold))
                                    Text(message.content).textSelection(.enabled)
                                    if let timestamp = message.timestamp {
                                        Text(timestamp).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .navigationTitle(thread.name)
                        }
                    }
                }
            }
        }
        .navigationTitle(label("查看 Web 聊天备份", "Read Web chat backup"))
        .fileImporter(isPresented: $pickArchive, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                guard try handle.seekToEnd() <= UInt64(WebV2ChatArchive.maxBytes) else {
                    throw WebV2ChatArchive.ArchiveError.tooLarge
                }
                try handle.seek(toOffset: 0)
                let data = try handle.read(upToCount: WebV2ChatArchive.maxBytes + 1) ?? Data()
                archive = try WebV2ChatArchive.decode(data)
                error = nil
            } catch {
                archive = nil
                self.error = error.localizedDescription
            }
        }
    }

    private func label(_ chinese: String, _ english: String) -> String {
        localization.uiLanguage.resolved == .zh ? chinese : english
    }
}
