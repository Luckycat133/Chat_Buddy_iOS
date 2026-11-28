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
    @State private var mergePreview: PortableBackupMergeService.Preview?
    @State private var confirmingMerge = false
    @State private var mergeStatus: String?
    @State private var mergedWindows: [String: Int] = [:]
    @State private var rebuiltChatIDs: Set<String> = []

    private var merger: PortableBackupMergeService { PortableBackupMergeService(http: cloud.http) }

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
                Button(label("选择 Web v2 备份", "Select a Web v2 backup")) {
                    clearMerge()
                    picking = true
                }
                if let pending {
                    Button(label("导入并替换已保存的备份", "Import and replace saved backup")) {
                        clearMerge()
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
                    clearMerge()
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
            if let restored, restored.account != nil, pending == nil {
                Section {
                    Button(label("预览合并差异（不写入）", "Preview merge (no writes)")) {
                        previewMerge(restored)
                    }
                    if let mergePreview {
                        mergeBreakdown(mergePreview, archive: restored)
                        if mergePreview.counts.hasInserts {
                            Button(label("查看合并确认", "Review merge confirmation")) {
                                confirmingMerge = true
                            }
                        } else {
                            Text(label("没有可安全新增的记录。", "Nothing can be safely added."))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(label("合并到在线私有聊天", "Merge into live private chats"))
                } footer: {
                    Text(label("仅合并当前账号的符合条件的私有记录。共享聊天及浏览器本地记录不回灌。同 ID 冲突保留线上记录，不修改成员或权限。",
                               "Only eligible private records for this account are merged. Shared chats and browser-local records are excluded. Live records win on conflict; membership and permissions are unchanged."))
                }
                .disabled(busy)
            }
            if let mergeStatus {
                Section {
                    Text(mergeStatus).foregroundStyle(.secondary)
                    ForEach(mergedWindows.keys.sorted(), id: \.self) { id in
                        if let start = mergedWindows[id] {
                            NavigationLink {
                                CloudChatView(conversationId: id, initialMessageCursor: start)
                            } label: {
                                let name = restored?.account?.conversations.first(where: { $0.id == id })?.publicName
                                if rebuiltChatIDs.contains(id) {
                                    Label(name ?? label("查看重建会话", "View rebuilt chat"),
                                          systemImage: "arrow.counterclockwise")
                                } else {
                                    Text(name ?? label("查看已恢复消息", "View restored messages"))
                                }
                            }
                        }
                    }
                } footer: {
                    if !mergedWindows.isEmpty {
                        Text(label("从新增位置分页查看在线消息，此处只读。请从聊天列表打开普通聊天以发送消息。", "Page through live messages from the restored position. This view is read-only; open the chat from the chat list to send messages."))
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(label("跨端账号备份", "Portable account backup"))
        .confirmationDialog(label("确认合并到在线私有聊天？", "Merge into live private chats?"),
                            isPresented: $confirmingMerge, titleVisibility: .visible,
                            presenting: mergePreview) { plan in
            Button(label("确认并仅新增", "Confirm and add missing records")) {
                commitMerge(plan)
            }
            Button(label("取消", "Cancel"), role: .cancel) {}
        } message: { plan in
            Text(label("重建私有会话 \(plan.counts.conversations.insert) 个，恢复消息 \(plan.counts.messages.insert) 条、附件 \(plan.counts.attachments.insert) 件。不会覆盖任何在线记录。",
                       "Rebuilds \(plan.counts.conversations.insert) private chats and restores \(plan.counts.messages.insert) messages and \(plan.counts.attachments.insert) attachments. No live records are overwritten."))
        }
        .onChange(of: cloud.sessionGeneration) { _, _ in
            clearMerge()
            pending = nil
            restored = nil
            exportDocument = nil
            exporting = false
            error = nil
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            clearMerge()
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

    @ViewBuilder private func mergeBreakdown(_ plan: PortableBackupMergeService.Preview,
                                             archive: PortableAccountBackup) -> some View {
        if let ids = plan.restoredConversationIds, !ids.isEmpty {
            mergeConversationNames(label("将重建的已删除私有会话", "Deleted private chats to rebuild"),
                                   ids: ids, archive: archive)
        }
        if let ids = plan.unsupportedConversationIds, !ids.isEmpty {
            mergeConversationNames(label("无法重建的会话（保持不变）", "Unavailable to rebuild (unchanged)"),
                                   ids: ids, archive: archive)
        }
        mergeCount(label("会话", "Chats"), counts: plan.counts.conversations,
                   conflictIDs: plan.conflicts?.conversations)
        mergeCount(label("消息", "Messages"), counts: plan.counts.messages,
                   conflictIDs: plan.conflicts?.messages)
        mergeCount(label("附件", "Attachments"), counts: plan.counts.attachments,
                   conflictIDs: plan.conflicts?.attachments)
    }

    private func mergeConversationNames(_ title: String, ids: [String], archive: PortableAccountBackup) -> some View {
        let chats = archive.account?.conversations ?? []
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(ids, id: \.self) { id in
                let name = chats.first { UUID(uuidString: $0.id) == UUID(uuidString: id) }?.publicName
                Text(name ?? id).font(.footnote)
            }
        }
    }

    @ViewBuilder private func mergeCount(_ title: String, counts: PortableBackupMergeService.Counts.Group,
                                        conflictIDs: [String]?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(label("新增 \(counts.insert) · 跳过 \(counts.skip) · 冲突 \(counts.conflict)",
                       "Add \(counts.insert) · Skip \(counts.skip) · Conflicts \(counts.conflict)"))
                .font(.footnote)
            if let conflictIDs, !conflictIDs.isEmpty {
                Text(conflictIDs.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private func clearMerge() {
        mergePreview = nil
        confirmingMerge = false
        mergeStatus = nil
        mergedWindows = [:]
        rebuiltChatIDs = []
    }

    private func previewMerge(_ backup: PortableAccountBackup) {
        clearMerge()
        run { generation in
            let client = merger
            guard let archiveID = backup.account?.accountId,
                  let activeID = await cloud.auth.currentAccountId(),
                  let archiveUUID = UUID(uuidString: archiveID),
                  archiveUUID == UUID(uuidString: activeID),
                  generation == cloud.sessionGeneration else {
                guard generation == cloud.sessionGeneration else { return }
                self.error = label("仅可预览当前账号的备份。", "Only the current account's backup can be previewed.")
                return
            }
            do {
                let plan = try await client.preview(for: backup)
                guard generation == cloud.sessionGeneration else { return }
                mergePreview = plan
            } catch PortableBackupMergeService.MergeError.archiveChanged {
                guard generation == cloud.sessionGeneration else { return }
                self.error = label("已保存备份已变化，请重新打开后预览。", "The saved backup changed. Open it again to preview.")
            } catch {
                guard generation == cloud.sessionGeneration else { return }
                self.error = label("无法预览。未发起在线合并。", "Preview failed. No live merge was requested.")
            }
        }
    }

    /// Only the confirmation dialog action calls this method. Consume the
    /// preview before the network request so a failed response cannot replay it.
    private func commitMerge(_ shown: PortableBackupMergeService.Preview) {
        guard !busy, let plan = mergePreview, plan.previewToken == shown.previewToken,
              let backup = restored, backup.sha256 == shown.archiveSha256,
              let account = backup.account, plan.counts.hasInserts else { return }
        let archivedIDs = Set(account.conversations.compactMap { UUID(uuidString: $0.id) })
        clearMerge()
        run { generation in
            let client = merger
            let receipt: PortableBackupMergeService.Receipt
            do {
                receipt = try await client.commit(plan, confirmed: true)
            } catch PortableBackupMergeService.MergeError.stalePreview {
                guard generation == cloud.sessionGeneration else { return }
                self.error = label("归档或在线记录已变化。请重新预览，不能沿用旧确认。",
                                   "The backup or live records changed. Refresh the preview before confirming again.")
                return
            } catch {
                guard generation == cloud.sessionGeneration else { return }
                self.error = label("无法确认合并结果。请先重新预览，不会自动重试。",
                                   "The merge result is unconfirmed. Preview again first; nothing will retry automatically.")
                return
            }
            guard generation == cloud.sessionGeneration else { return }
            guard Set(receipt.affectedConversationIds.compactMap { UUID(uuidString: $0) })
                .isSubset(of: archivedIDs) else {
                self.error = label("无法核对回执范围，请重新预览。不会自动重试。",
                                   "The receipt scope could not be verified. Preview again; nothing will retry automatically.")
                return
            }
            mergedWindows = receipt.affectedConversationStarts
            rebuiltChatIDs = Set(receipt.restoredConversationIds ?? [])
            mergeStatus = rebuiltChatIDs.isEmpty
                ? label("私有聊天合并已确认。", "Private-chat merge confirmed.")
                : label("私有会话重建已确认。", "Private-chat rebuild confirmed.")
            do {
                try await cloud.refreshAfterPortableMerge(receipt, generation: generation)
            } catch {
                guard generation == cloud.sessionGeneration else { return }
                mergeStatus = label("云端合并已确认。本机尚未同步，打开对应会话可从云端读取。",
                                    "Cloud merge confirmed. Local refresh failed; open the affected chat to read from the server.")
            }
        }
    }

    private func prepareExport(_ backup: PortableAccountBackup) {
        exportDocument = BackupDocument(data: backup.document)
        exporting = true
    }

    private func run(_ work: @escaping @MainActor (UUID) async throws -> Void) {
        let generation = cloud.sessionGeneration
        guard !busy else { return }
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
