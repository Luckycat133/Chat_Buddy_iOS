import Foundation

// MARK: - Data Types

struct IndexedChunk: Codable, Identifiable {
    var id: String { "\(documentId)_\(chunkIndex)" }
    let documentId: String
    let documentName: String
    let chunkIndex: Int
    let content: String
    let keywords: [String]
    let embedding: [Double]
}

struct SearchResult: Identifiable {
    var id: String { "\(documentId)_\(chunkIndex)" }
    let documentId: String
    let documentName: String
    let chunkIndex: Int
    let content: String
    let score: Double
}

// MARK: - RAGService

/// Lightweight on-device RAG pipeline: chunk → keyword-extract → BM25/Jaccard hybrid search.
/// Port of ragUtils.js — TF-IDF indexing, BM25 scoring, and hybrid retrieval.
enum RAGService {

    // MARK: - Constants

    private static let defaultChunkSize = 500
    private static let defaultOverlap = 100
    private static let embeddingDim = 256
    private static let bm25K1 = 1.5
    private static let bm25B = 0.75
    private static let storageKey = "chat-buddy-rag-index"

    private static let stopWordsEn: Set<String> = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
        "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
        "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their",
        "what", "so", "up", "out", "if", "about", "who", "get", "which",
        "go", "me", "when", "make", "can", "like", "time", "no", "just",
        "him", "know", "take", "people", "into", "year", "your", "good",
        "some", "could", "them", "see", "other", "than", "then", "now",
        "look", "only", "come", "its", "over", "think", "also", "back",
        "after", "use", "two", "how", "our", "work", "first", "well",
        "way", "even", "new", "want", "because", "any", "these", "give",
        "day", "most", "us", "is", "was", "are", "were", "been", "has", "had",
        "did", "does", "being", "am"
    ]

    private static let stopWordsZh: Set<String> = [
        "的", "了", "在", "是", "我", "有", "和", "就", "不", "人",
        "都", "一", "一个", "上", "也", "很", "到", "说", "要", "去",
        "你", "会", "着", "没有", "看", "好", "自己", "这"
    ]

    // MARK: - Text Chunking

    /// Split text into overlapping chunks, respecting paragraph and sentence boundaries.
    static func chunkText(_ text: String, chunkSize: Int = 500, overlap: Int = 100) -> [String] {
        let paragraphs = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return text.isEmpty ? [] : [text] }

        var chunks: [String] = []
        var current = ""

        for para in paragraphs {
            if para.count > chunkSize {
                // Oversized paragraph — split on sentence boundaries
                if !current.isEmpty {
                    chunks.append(current)
                    current = String(current.suffix(overlap))
                }
                let sentences = splitSentences(para)
                var sentGroup = ""
                for sent in sentences {
                    if sentGroup.count + sent.count > chunkSize && !sentGroup.isEmpty {
                        chunks.append(sentGroup)
                        sentGroup = String(sentGroup.suffix(overlap))
                    }
                    sentGroup += (sentGroup.isEmpty ? "" : " ") + sent
                }
                if !sentGroup.isEmpty { current = sentGroup }
            } else if current.count + para.count + 1 > chunkSize {
                chunks.append(current)
                current = String(current.suffix(overlap)) + "\n" + para
            } else {
                current += (current.isEmpty ? "" : "\n") + para
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Best-effort sentence splitting that handles English (.!?) and Chinese (。！？) terminators.
    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?。！？".contains(ch) {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append(current.trimmingCharacters(in: .whitespaces))
        }
        return sentences
    }

    // MARK: - Keyword Extraction

    /// TF-based keyword extraction: tokenize, remove stop words, return top-N by frequency.
    static func extractKeywords(_ text: String, topN: Int = 20) -> [String] {
        let lower = text.lowercased()
        // Match words (including Chinese characters)
        let pattern = "[a-z0-9\\u4e00-\\u9fff]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
        let tokens = matches.compactMap { Range($0.range, in: lower).map { String(lower[$0]) } }
            .filter { $0.count > 2 && !stopWordsEn.contains($0) && !stopWordsZh.contains($0) }

        var freq: [String: Int] = [:]
        for t in tokens { freq[t, default: 0] += 1 }
        return freq.sorted { $0.value > $1.value }.prefix(topN).map(\.key)
    }

    // MARK: - Lightweight Embedding (hash bag-of-words)

    /// Hash-based bag-of-words embedding (same as web's buildLightweightEmbedding).
    static func buildEmbedding(_ text: String, dim: Int = 256) -> [Double] {
        var vec = [Double](repeating: 0, count: dim)
        let tokens = extractKeywords(text, topN: 100)
        for token in tokens {
            let idx = hashToken(token, dim: dim)
            vec[idx] += 1
        }
        // L2 normalize
        let norm = sqrt(vec.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { for i in 0..<dim { vec[i] /= norm } }
        return vec
    }

    private static func hashToken(_ token: String, dim: Int) -> Int {
        var hash = 0
        for ch in token.unicodeScalars {
            hash = ((hash << 5) &- hash) &+ Int(ch.value)
        }
        return abs(hash) % dim
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot = 0.0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot // Vectors are pre-normalized
    }

    // MARK: - BM25

    private static func bm25Score(queryKeywords: [String], chunkContent: String, avgDocLength: Double) -> Double {
        let lower = chunkContent.lowercased()
        let docLen = Double(lower.count)
        var score = 0.0
        for kw in queryKeywords {
            let tf = Double(lower.components(separatedBy: kw).count - 1)
            guard tf > 0 else { continue }
            score += (tf * (bm25K1 + 1)) / (tf + bm25K1 * (1.0 - bm25B + bm25B * docLen / max(1, avgDocLength)))
        }
        return score
    }

    private static func jaccardSimilarity(_ a: [String], _ b: [String]) -> Double {
        let setA = Set(a)
        let setB = Set(b)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    // MARK: - Indexing

    /// Index a document: chunk it, extract keywords, build embeddings for each chunk.
    static func indexDocument(id: String, name: String, content: String) -> [IndexedChunk] {
        let chunks = chunkText(content)
        return chunks.enumerated().map { (i, chunk) in
            IndexedChunk(
                documentId: id,
                documentName: name,
                chunkIndex: i,
                content: chunk,
                keywords: extractKeywords(chunk),
                embedding: buildEmbedding(chunk)
            )
        }
    }

    // MARK: - Search

    /// Hybrid search: BM25 (50%) + Jaccard (30%) + vector cosine (20%).
    static func searchDocuments(query: String, indexedChunks: [IndexedChunk], topK: Int = 3) -> [SearchResult] {
        guard !indexedChunks.isEmpty else { return [] }

        let queryKeywords = extractKeywords(query)
        let queryEmbedding = buildEmbedding(query)
        let avgDocLen = Double(indexedChunks.reduce(0) { $0 + $1.content.count }) / Double(indexedChunks.count)

        struct Scored {
            let chunk: IndexedChunk
            let bm25: Double
            let jaccard: Double
            let vector: Double
        }

        var scored: [Scored] = indexedChunks.map { chunk in
            Scored(
                chunk: chunk,
                bm25: bm25Score(queryKeywords: queryKeywords, chunkContent: chunk.content, avgDocLength: avgDocLen),
                jaccard: jaccardSimilarity(queryKeywords, chunk.keywords),
                vector: max(0, cosineSimilarity(queryEmbedding, chunk.embedding))
            )
        }

        let maxBM25 = scored.map(\.bm25).max() ?? 1
        let normalizer = maxBM25 > 0 ? maxBM25 : 1.0

        return scored
            .map { s in
                let hybrid = 0.5 * (s.bm25 / normalizer) + 0.3 * s.jaccard + 0.2 * s.vector
                return (s.chunk, hybrid)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { SearchResult(documentId: $0.0.documentId, documentName: $0.0.documentName, chunkIndex: $0.0.chunkIndex, content: $0.0.content, score: $0.1) }
    }

    /// Build a RAG context string for injection into the system prompt.
    static func buildRAGContext(query: String, indexedChunks: [IndexedChunk], topK: Int = 3) -> String? {
        let results = searchDocuments(query: query, indexedChunks: indexedChunks, topK: topK)
        guard !results.isEmpty else { return nil }
        let sources = results.map { "[\($0.documentName)#\($0.chunkIndex)]:\n\($0.content)" }
        return sources.joined(separator: "\n---\n")
    }

    // MARK: - Persistence

    static func saveIndex(_ chunks: [IndexedChunk]) {
        StorageService.shared.set(storageKey, value: chunks)
    }

    static func loadIndex() -> [IndexedChunk] {
        StorageService.shared.get(storageKey, default: [])
    }

    static func addDocumentToIndex(id: String, name: String, content: String, existing: [IndexedChunk]? = nil) -> [IndexedChunk] {
        var current = existing ?? loadIndex()
        current.removeAll { $0.documentId == id }
        current.append(contentsOf: indexDocument(id: id, name: name, content: content))
        saveIndex(current)
        return current
    }

    static func removeDocumentFromIndex(documentId: String, existing: [IndexedChunk]? = nil) -> [IndexedChunk] {
        var current = existing ?? loadIndex()
        current.removeAll { $0.documentId == documentId }
        saveIndex(current)
        return current
    }
}
