import SwiftUI

private struct KnowledgeNode: Identifiable, Codable {
    var id: String
    var name: String
    var nameZh: String
    var category: String
    var description: String
    var descriptionZh: String
    var difficulty: Int
    var custom: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        nameZh: String,
        category: String,
        description: String,
        descriptionZh: String,
        difficulty: Int = 1,
        custom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.nameZh = nameZh
        self.category = category
        self.description = description
        self.descriptionZh = descriptionZh
        self.difficulty = difficulty
        self.custom = custom
    }
}

/// A directed edge between two knowledge nodes.
private struct KnowledgeEdge: Identifiable, Codable {
    var id: String
    var sourceId: String
    var targetId: String
    var label: String
    var labelZh: String

    init(id: String = UUID().uuidString, sourceId: String, targetId: String, label: String, labelZh: String = "") {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.label = label
        self.labelZh = labelZh
    }
}

struct KnowledgeGraphView: View {
    @Environment(LocalizationManager.self) private var localization

    @State private var customNodes: [KnowledgeNode] = StorageService.shared.get("knowledgeGraph.custom", default: [])
    @State private var edges: [KnowledgeEdge] = StorageService.shared.get("knowledgeGraph.edges", default: [])
    @State private var search = ""
    @State private var showAdd = false
    @State private var showAddEdge = false
    @State private var draftNameEn = ""
    @State private var draftNameZh = ""
    @State private var draftCategory = "custom"
    @State private var draftDescEn = ""
    @State private var draftDescZh = ""
    @State private var edgeSourceId = ""
    @State private var edgeTargetId = ""
    @State private var edgeLabelEn = ""
    @State private var edgeLabelZh = ""

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private let builtins: [KnowledgeNode] = [
        .init(id: "kg-swift", name: "Swift Basics", nameZh: "Swift 基础", category: "programming", description: "Variables, functions, optionals", descriptionZh: "变量、函数、可选值", difficulty: 1),
        .init(id: "kg-swiftui", name: "SwiftUI Layout", nameZh: "SwiftUI 布局", category: "programming", description: "VStack, HStack, state-driven UI", descriptionZh: "VStack、HStack、状态驱动 UI", difficulty: 2),
        .init(id: "kg-network", name: "Networking", nameZh: "网络请求", category: "programming", description: "URLSession and async/await", descriptionZh: "URLSession 与 async/await", difficulty: 2),
        .init(id: "kg-testing", name: "Testing", nameZh: "测试", category: "programming", description: "Unit tests and UI tests", descriptionZh: "单元测试与 UI 测试", difficulty: 2),
        .init(id: "kg-prompt", name: "Prompt Design", nameZh: "提示词设计", category: "language", description: "Clear structure and constraints", descriptionZh: "清晰结构与约束", difficulty: 1),
    ]

    private var nodes: [KnowledgeNode] {
        let all = builtins + customNodes
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || $0.nameZh.localizedCaseInsensitiveContains(q)
            || $0.category.localizedCaseInsensitiveContains(q)
        }
    }

    private var builtinEdges: [KnowledgeEdge] {
        [
            KnowledgeEdge(id: "edge-swift-swiftui", sourceId: "kg-swift", targetId: "kg-swiftui", label: "enables", labelZh: "是基础"),
            KnowledgeEdge(id: "edge-swiftui-testing", sourceId: "kg-swiftui", targetId: "kg-testing", label: "tested by", labelZh: "可测试"),
            KnowledgeEdge(id: "edge-network-swift", sourceId: "kg-network", targetId: "kg-swift", label: "uses", labelZh: "使用"),
        ]
    }

    private var allEdges: [KnowledgeEdge] { builtinEdges + edges }

    var body: some View {
        List {
            Section {
                TextField(isZh ? "搜索知识点" : "Search concepts", text: $search)
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label(isZh ? "新增知识点" : "Add Concept", systemImage: "plus.circle")
                }
                Button {
                    showAddEdge = true
                } label: {
                    Label(isZh ? "新增关系" : "Add Relationship", systemImage: "arrow.triangle.branch")
                }
            }

            // Edges section
            if !allEdges.isEmpty {
                Section(isZh ? "关系" : "Relationships") {
                    ForEach(allEdges) { edge in
                        HStack(spacing: DSSpacing.xs) {
                            let sourceName = nodes.first { $0.id == edge.sourceId }.map { isZh ? $0.nameZh : $0.name } ?? edge.sourceId
                            let targetName = nodes.first { $0.id == edge.targetId }.map { isZh ? $0.nameZh : $0.name } ?? edge.targetId
                            Text(sourceName)
                                .font(DSTypography.caption1.weight(.semibold))
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(targetName)
                                .font(DSTypography.caption1.weight(.semibold))
                            Spacer()
                            Text(isZh ? edge.labelZh : edge.label)
                                .font(DSTypography.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            if !builtinEdges.contains(where: { $0.id == edge.id }) {
                                Button(role: .destructive) {
                                    edges.removeAll { $0.id == edge.id }
                                    saveEdges()
                                } label: {
                                    Label(isZh ? "删除" : "Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            Section(isZh ? "知识节点" : "Nodes") {
                if nodes.isEmpty {
                    Text(isZh ? "没有匹配结果" : "No matching nodes")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(nodes) { node in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(isZh ? node.nameZh : node.name)
                                    .font(DSTypography.footnote.weight(.semibold))
                                Spacer()
                                Text(node.category)
                                    .font(DSTypography.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            Text(isZh ? node.descriptionZh : node.description)
                                .font(DSTypography.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(repeating: "⭐", count: max(1, node.difficulty)))
                                .font(DSTypography.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 2)
                        .swipeActions {
                            if node.custom {
                                Button(role: .destructive) {
                                    customNodes.removeAll { $0.id == node.id }
                                    save()
                                } label: {
                                    Label(isZh ? "删除" : "Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(isZh ? "知识图谱" : "Knowledge Graph")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section {
                        TextField(isZh ? "英文名" : "English name", text: $draftNameEn)
                        TextField(isZh ? "中文名" : "Chinese name", text: $draftNameZh)
                        TextField(isZh ? "分类" : "Category", text: $draftCategory)
                    }
                    Section {
                        TextField(isZh ? "英文描述" : "English description", text: $draftDescEn, axis: .vertical)
                            .lineLimit(1...3)
                        TextField(isZh ? "中文描述" : "Chinese description", text: $draftDescZh, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }
                .navigationTitle(isZh ? "新增知识点" : "Add Concept")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isZh ? "取消" : "Cancel") { showAdd = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isZh ? "保存" : "Save") {
                            let en = draftNameEn.trimmingCharacters(in: .whitespacesAndNewlines)
                            let zh = draftNameZh.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !en.isEmpty || !zh.isEmpty else { return }
                            let node = KnowledgeNode(
                                name: en.isEmpty ? zh : en,
                                nameZh: zh.isEmpty ? en : zh,
                                category: draftCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "custom" : draftCategory,
                                description: draftDescEn,
                                descriptionZh: draftDescZh,
                                difficulty: 1,
                                custom: true
                            )
                            customNodes.insert(node, at: 0)
                            save()
                            draftNameEn = ""
                            draftNameZh = ""
                            draftCategory = "custom"
                            draftDescEn = ""
                            draftDescZh = ""
                            showAdd = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddEdge) {
            AddEdgeSheet(
                nodes: nodes,
                isZh: isZh,
                sourceId: $edgeSourceId,
                targetId: $edgeTargetId,
                labelEn: $edgeLabelEn,
                labelZh: $edgeLabelZh,
                isPresented: $showAddEdge
            ) {
                let en = edgeLabelEn.trimmingCharacters(in: .whitespacesAndNewlines)
                let zh = edgeLabelZh.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !edgeSourceId.isEmpty, !edgeTargetId.isEmpty else { return }
                let edge = KnowledgeEdge(
                    sourceId: edgeSourceId,
                    targetId: edgeTargetId,
                    label: en.isEmpty ? zh : en,
                    labelZh: zh.isEmpty ? en : zh
                )
                edges.insert(edge, at: 0)
                saveEdges()
                edgeSourceId = ""
                edgeTargetId = ""
                edgeLabelEn = ""
                edgeLabelZh = ""
            }
        }
    }

    private func save() {
        StorageService.shared.set("knowledgeGraph.custom", value: customNodes)
    }

    private func saveEdges() {
        StorageService.shared.set("knowledgeGraph.edges", value: edges)
    }
}

// MARK: - Add Edge Sheet

private struct AddEdgeSheet: View {
    let nodes: [KnowledgeNode]
    let isZh: Bool
    @Binding var sourceId: String
    @Binding var targetId: String
    @Binding var labelEn: String
    @Binding var labelZh: String
    @Binding var isPresented: Bool
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(isZh ? "起点" : "Source", selection: $sourceId) {
                        Text(isZh ? "选择" : "Select").tag("")
                        ForEach(nodes) { node in
                            Text(isZh ? node.nameZh : node.name).tag(node.id)
                        }
                    }
                    Picker(isZh ? "终点" : "Target", selection: $targetId) {
                        Text(isZh ? "选择" : "Select").tag("")
                        ForEach(nodes) { node in
                            Text(isZh ? node.nameZh : node.name).tag(node.id)
                        }
                    }
                }
                Section {
                    TextField(isZh ? "关系描述 (英文)" : "Relationship (English)", text: $labelEn)
                    TextField(isZh ? "关系描述 (中文)" : "Relationship (Chinese)", text: $labelZh)
                }
            }
            .navigationTitle(isZh ? "新增关系" : "Add Relationship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isZh ? "取消" : "Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZh ? "保存" : "Save") {
                        onSave()
                        isPresented = false
                    }
                    .disabled(sourceId.isEmpty || targetId.isEmpty || (labelEn.isEmpty && labelZh.isEmpty))
                }
            }
        }
    }
}
