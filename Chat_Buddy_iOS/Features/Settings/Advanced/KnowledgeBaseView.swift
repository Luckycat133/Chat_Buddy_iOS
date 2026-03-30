import SwiftUI
import UniformTypeIdentifiers

private struct KnowledgeDocument: Identifiable, Codable {
    var id: String
    var name: String
    var content: String
    var size: Int
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, content: String, size: Int, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.content = content
        self.size = size
        self.createdAt = createdAt
    }
}

private struct KnowledgeBaseData: Codable {
    var ragEnabled: Bool
    var docs: [KnowledgeDocument]

    static let empty = KnowledgeBaseData(ragEnabled: true, docs: [])
}

struct KnowledgeBaseView: View {
    @Environment(LocalizationManager.self) private var localization

    @State private var data: KnowledgeBaseData = StorageService.shared.get("knowledgeBase", default: .empty)
    @State private var showImporter = false
    @State private var errorText: String?

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    var body: some View {
        List {
            Section {
                Toggle(isZh ? "启用 RAG" : "Enable RAG", isOn: Binding(
                    get: { data.ragEnabled },
                    set: {
                        data.ragEnabled = $0
                        save()
                    }
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

                if !data.docs.isEmpty {
                    Button(role: .destructive) {
                        data.docs.removeAll()
                        save()
                    } label: {
                        Label(isZh ? "清空文档" : "Clear All", systemImage: "trash")
                    }
                }
            }

            Section(isZh ? "文档" : "Documents") {
                if data.docs.isEmpty {
                    Text(isZh ? "暂无文档" : "No documents yet")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(data.docs) { doc in
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
                                data.docs.removeAll { $0.id == doc.id }
                                save()
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
            let doc = KnowledgeDocument(name: url.lastPathComponent, content: text, size: fileData.count)
            data.docs.insert(doc, at: 0)
            save()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func save() {
        StorageService.shared.set("knowledgeBase", value: data)
    }

    private func humanSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }
}
