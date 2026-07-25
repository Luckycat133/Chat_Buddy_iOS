import Foundation

// MARK: - Data Models

/// A document imported into the user's local knowledge base.
struct KnowledgeDocument: Identifiable, Codable {
    var id: String
    var name: String
    var content: String
    var size: Int
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        content: String,
        size: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.size = size
        self.createdAt = createdAt
    }
}

/// Persisted shape of the knowledge base: the RAG toggle plus imported documents.
struct KnowledgeBaseData: Codable {
    var ragEnabled: Bool
    var docs: [KnowledgeDocument]

    static let empty = KnowledgeBaseData(ragEnabled: true, docs: [])
}

// MARK: - KnowledgeBaseStore

/// Observable store for the local knowledge base.
///
/// Owns the RAG toggle and imported documents, persists them to
/// `chat-buddy:knowledgeBase`, and keeps `RAGService`'s search index in sync
/// on add/remove/clear.
@Observable final class KnowledgeBaseStore: StoreReloading {
    private(set) var ragEnabled: Bool = true
    private(set) var documents: [KnowledgeDocument] = []

    private static let storageKey = "knowledgeBase"

    init() {
        load()
    }

    /// Reload all in-memory state from persisted storage.
    func reloadFromStorage() {
        load()
    }

    // MARK: - Mutations

    func setRagEnabled(_ enabled: Bool) {
        ragEnabled = enabled
        save()
    }

    /// Imports a document, persists it, and indexes its content for RAG search.
    /// Returns the newly created document.
    @discardableResult
    func importDocument(name: String, content: String, size: Int) -> KnowledgeDocument {
        let doc = KnowledgeDocument(name: name, content: content, size: size)
        documents.insert(doc, at: 0)
        save()
        RAGService.addDocumentToIndex(id: doc.id, name: doc.name, content: doc.content)
        return doc
    }

    func deleteDocument(id: String) {
        guard documents.contains(where: { $0.id == id }) else { return }
        documents.removeAll { $0.id == id }
        save()
        RAGService.removeDocumentFromIndex(documentId: id)
    }

    func clearAll() {
        for doc in documents {
            RAGService.removeDocumentFromIndex(documentId: doc.id)
        }
        documents.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        let data: KnowledgeBaseData = StorageService.shared.get(Self.storageKey, default: .empty)
        ragEnabled = data.ragEnabled
        documents = data.docs
    }

    private func save() {
        let data = KnowledgeBaseData(ragEnabled: ragEnabled, docs: documents)
        StorageService.shared.set(Self.storageKey, value: data)
    }
}
