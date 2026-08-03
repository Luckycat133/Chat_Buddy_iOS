import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeBaseView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(KnowledgeBaseStore.self) private var store

    @State private var showImporter = false
    @State private var errorText: String?

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    var body: some View {
        List {
            Section {
                Toggle(isZh ? "启用 RAG" : "Enable RAG", isOn: Binding(
                    get: { store.ragEnabled },
                    set: { store.setRagEnabled($0) }
                ))
            } footer: {
                Text(isZh ? "启用后会优先使用知识库内容辅助回答。" : "When enabled, responses can prioritize knowledge-base context.")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label(isZh ? "导入文档" : "Import Document", systemImage: "square.and.arrow.down")
                }

                if !store.documents.isEmpty {
                    Button(role: .destructive) {
                        store.clearAll()
                    } label: {
                        Label(isZh ? "清空文档" : "Clear All", systemImage: "trash")
                    }
                }
            }

            Section(isZh ? "文档" : "Documents") {
                if store.documents.isEmpty {
                    Text(isZh ? "暂无文档" : "No documents yet")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.documents) { doc in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(doc.name)
                                .font(DSTypography.footnote.weight(.semibold))
                            Text((isZh ? "大小" : "Size") + ": " + humanSize(doc.size))
                                .font(DSTypography.caption2)
                                .foregroundStyle(.secondary)
                            Text(doc.createdAt, style: .relative)
                                .font(DSTypography.caption2)
                                .foregroundStyle(.tertiary)
                            Text(doc.content)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(4)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                        .padding(.vertical, 2)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteDocument(id: doc.id)
                            } label: {
                                Label(isZh ? "删除" : "Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(DSTypography.caption1)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(isZh ? "知识库" : "Knowledge Base")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .text, .utf8PlainText, .json, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importFile(at: url)
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }

    private func importFile(at url: URL) {
        do {
            let granted = url.startAccessingSecurityScopedResource()
            defer {
                if granted { url.stopAccessingSecurityScopedResource() }
            }
            let fileData = try Data(contentsOf: url)
            let text = String(data: fileData, encoding: .utf8) ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorText = isZh ? "文档内容为空或编码不支持" : "Empty document or unsupported encoding"
                return
            }
            store.importDocument(name: url.lastPathComponent, content: text, size: fileData.count)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func humanSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }
}
