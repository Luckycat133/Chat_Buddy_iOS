import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PortableAccountBackupView: View {
    @EnvironmentObject private var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var localization
    @State private var picking = false
    @State private var exporting = false
    @State private var busy = false
    @State private var error: String?
    @State private var pending: PortableAccountBackup?
    @State private var restored: PortableAccountBackup?
    @State private var exportDocument: BackupDocument?

    private var service: PortableAccountBackupService { PortableAccountBackupService(http: cloud.http) }

    var body: some View {
        List {
            Section {
                Button(label("导出当前帐号聊天", "Export current account chats")) {
                    run { generation in
                        let backup = try await service.read(live: true)
                        guard generation == cloud.sessionGeneration else { return }
                        prepareExport(backup)
                    }
                }
                Button(label("选择 Web v2 备份", "Select a Web v2 backup")) { picking = true }
                if let pending {
                    Button(label("导入并替换已保存的备份", "Import and replace saved backup")) {
                        run { generation in
                            let importer = service
                            _ = try await importer.restore(pending)
                            guard generation == cloud.sessionGeneration else { return }
                            let reread = try await importer.read(live: false)
                            guard generation == cloud.sessionGeneration else { return }
                            guard reread.sha256 == pending.sha256 else { throw PortableAccountBackup.BackupError.transferMismatch }
                            restored = reread
                            self.pending = nil
                        }
                    }
                }
                Button(label("读取已导入备份", "Open imported backup")) {
                    run { generation in
                        let backup = try await service.read(live: false)
                        guard generation == cloud.sessionGeneration else { return }
                        restored = backup
                    }
                }
            } footer: {
                Text(label("备份与当前账号绑定。导入只替换帐号里保存的备份，不会更改在线会话、成员身份或权限。单个文件最多 4 MiB。",
                           "Backups bind to this account. Import replaces its saved backup, not live conversations, members, or permissions. Maximum 4 MiB."))
            }
            .disabled(busy)
            if let restored {
                Section(label("恢复的备份", "Restored backup")) {
                    Button(label("原样重新导出", "Re-export original backup")) { prepareExport(restored) }
                    ForEach(restored.account?.conversations ?? []) { conversation in
                        NavigationLink(conversation.publicName ?? conversation.id) {
                            List(conversation.messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.senderActorId).font(.caption.weight(.semibold))
                                    Text(message.content).textSelection(.enabled)
                                    ForEach(Array((message.attachmentIds ?? []).enumerated()), id: \.offset) { _, id in
                                        if let attachment = restored.attachments.first(where: { $0.id == id }) {
                                            attachmentContent(attachment)
                                        }
                                    }
                                }
                            }
                            .navigationTitle(conversation.publicName ?? conversation.id)
                        }
                    }
                    ForEach(restored.localChats) { thread in
                        NavigationLink(thread.name) {
                            List(thread.messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.senderID).font(.caption.weight(.semibold))
                                    if !message.content.hasPrefix("[IMG:") {
                                        Text(message.content).textSelection(.enabled)
                                    }
                                    ForEach(restored.attachments(for: message)) { attachment in
                                        attachmentContent(attachment)
                                    }
                                }
                            }
                            .navigationTitle(thread.name)
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(label("跨端账号备份", "Portable account backup"))
        .onChange(of: cloud.sessionGeneration) { _, _ in
            pending = nil
            restored = nil
            exportDocument = nil
            exporting = false
            error = nil
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            pending = nil
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                guard try handle.seekToEnd() <= UInt64(PortableAccountBackup.maxBytes) else {
                    throw PortableAccountBackup.BackupError.invalidDocument
                }
                try handle.seek(toOffset: 0)
                let input = try handle.read(upToCount: PortableAccountBackup.maxBytes + 1) ?? Data()
                pending = try PortableAccountBackup(document: input)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                      defaultFilename: "chat-buddy-web-v2.json") { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder private func attachmentContent(_ attachment: PortableAccountBackup.Attachment) -> some View {
        if ["image/png", "image/jpeg"].contains(attachment.mimeType),
           let bytes = attachment.verifiedInlineBytes,
           let image = UIImage(data: bytes) {
            Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(attachment.name)
        } else {
            Label(attachment.name + label("（附件占位）", " (attachment placeholder)"), systemImage: "paperclip")
                .font(.caption)
        }
    }

    private func prepareExport(_ backup: PortableAccountBackup) {
        exportDocument = BackupDocument(data: backup.document)
        exporting = true
    }

    private func run(_ work: @escaping @MainActor (UUID) async throws -> Void) {
        let generation = cloud.sessionGeneration
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await work(generation) }
            catch {
                if generation == cloud.sessionGeneration { self.error = error.localizedDescription }
            }
        }
    }

    private func label(_ zh: String, _ en: String) -> String {
        localization.uiLanguage.resolved == .zh ? zh : en
    }
}
