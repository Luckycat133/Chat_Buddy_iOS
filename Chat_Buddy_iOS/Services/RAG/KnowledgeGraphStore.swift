import Foundation

// MARK: - Data Models

/// A node in the knowledge graph (built-in or user-created).
struct KnowledgeNode: Identifiable, Codable {
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
struct KnowledgeEdge: Identifiable, Codable {
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

// MARK: - KnowledgeGraphStore

/// Observable store for the user-created knowledge graph state.
///
/// Persists custom nodes at `chat-buddy:knowledgeGraph.custom` and custom edges
/// at `chat-buddy:knowledgeGraph.edges`. Built-in nodes/edges remain hardcoded
/// in the view layer (immutable presentation data).
@Observable final class KnowledgeGraphStore: StoreReloading {
    private(set) var customNodes: [KnowledgeNode] = []
    private(set) var edges: [KnowledgeEdge] = []

    private static let customNodesKey = "knowledgeGraph.custom"
    private static let edgesKey = "knowledgeGraph.edges"

    init() {
        load()
    }

    /// Reload all in-memory state from persisted storage.
    func reloadFromStorage() {
        load()
    }

    // MARK: - Mutations

    /// Adds a custom node and persists. Returns the new node.
    @discardableResult
    func addCustomNode(
        name: String,
        nameZh: String,
        category: String,
        description: String,
        descriptionZh: String,
        difficulty: Int = 1
    ) -> KnowledgeNode {
        let node = KnowledgeNode(
            name: name,
            nameZh: nameZh,
            category: category,
            description: description,
            descriptionZh: descriptionZh,
            difficulty: difficulty,
            custom: true
        )
        customNodes.insert(node, at: 0)
        saveNodes()
        return node
    }

    func deleteCustomNode(id: String) {
        customNodes.removeAll { $0.id == id }
        saveNodes()
    }

    /// Adds a custom edge and persists. Returns the new edge.
    @discardableResult
    func addEdge(sourceId: String, targetId: String, label: String, labelZh: String) -> KnowledgeEdge {
        let edge = KnowledgeEdge(sourceId: sourceId, targetId: targetId, label: label, labelZh: labelZh)
        edges.insert(edge, at: 0)
        saveEdges()
        return edge
    }

    func deleteEdge(id: String) {
        edges.removeAll { $0.id == id }
        saveEdges()
    }

    // MARK: - Persistence

    private func load() {
        customNodes = StorageService.shared.get(Self.customNodesKey, default: [KnowledgeNode]())
        edges = StorageService.shared.get(Self.edgesKey, default: [KnowledgeEdge]())
    }

    private func saveNodes() {
        StorageService.shared.set(Self.customNodesKey, value: customNodes)
    }

    private func saveEdges() {
        StorageService.shared.set(Self.edgesKey, value: edges)
    }
}
