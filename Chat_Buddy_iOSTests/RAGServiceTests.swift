import XCTest
@testable import Chat_Buddy_iOS

final class RAGServiceTests: XCTestCase {

    // MARK: - Text Chunking

    func testChunkEmptyText() {
        let chunks = RAGService.chunkText("")
        XCTAssertTrue(chunks.isEmpty)
    }

    func testChunkShortText() {
        let chunks = RAGService.chunkText("Hello world.")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first, "Hello world.")
    }

    func testChunkRespectsSizeLimit() {
        // Build text that exceeds default chunk size (500)
        let paragraph = String(repeating: "word ", count: 120) // ~600 chars
        let chunks = RAGService.chunkText(paragraph, chunkSize: 200, overlap: 40)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            // Allow some tolerance for overlap
            XCTAssertLessThanOrEqual(chunk.count, 300)
        }
    }

    func testChunkMultipleParagraphs() {
        let text = (1...10).map { "Paragraph \($0). " + String(repeating: "text ", count: 30) }.joined(separator: "\n")
        let chunks = RAGService.chunkText(text, chunkSize: 200, overlap: 30)
        XCTAssertGreaterThan(chunks.count, 1)
    }

    // MARK: - Keyword Extraction

    func testExtractKeywordsFromEnglish() {
        let text = "Swift programming language. Swift is powerful and fast. Swift supports concurrency."
        let keywords = RAGService.extractKeywords(text, topN: 5)
        XCTAssertTrue(keywords.contains("swift"))
    }

    func testExtractKeywordsRemoveStopWords() {
        let text = "the quick brown fox jumps over the lazy dog and the cat"
        let keywords = RAGService.extractKeywords(text, topN: 10)
        // "the", "and", "over" should be filtered
        XCTAssertFalse(keywords.contains("the"))
        XCTAssertFalse(keywords.contains("and"))
    }

    func testExtractKeywordsFromChinese() {
        let text = "机器学习是人工智能的重要分支。深度学习在计算机视觉中取得了巨大成功。"
        let keywords = RAGService.extractKeywords(text, topN: 5)
        XCTAssertFalse(keywords.isEmpty)
    }

    func testExtractKeywordsEmpty() {
        let keywords = RAGService.extractKeywords("", topN: 5)
        XCTAssertTrue(keywords.isEmpty)
    }

    // MARK: - Embedding

    func testBuildEmbeddingDimension() {
        let embedding = RAGService.buildEmbedding("test document content", dim: 128)
        XCTAssertEqual(embedding.count, 128)
    }

    func testBuildEmbeddingNormalized() {
        let embedding = RAGService.buildEmbedding("sample text for normalization test case")
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        // Normalized vector should have length ~1
        if norm > 0 { XCTAssertEqual(norm, 1.0, accuracy: 0.01) }
    }

    // MARK: - Document Indexing

    func testIndexDocument() {
        let chunks = RAGService.indexDocument(id: "doc1", name: "Test Doc", content: "Hello world. This is a test document with enough content to index properly.")
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(chunks.first?.documentId, "doc1")
        XCTAssertEqual(chunks.first?.documentName, "Test Doc")
    }

    // MARK: - Search

    func testSearchEmptyIndex() {
        let results = RAGService.searchDocuments(query: "test", indexedChunks: [], topK: 3)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchFindsRelevantDocument() {
        let content = "Swift programming language is used for iOS development. SwiftUI makes building user interfaces easy."
        let chunks = RAGService.indexDocument(id: "swift-doc", name: "Swift Guide", content: content)
        let results = RAGService.searchDocuments(query: "SwiftUI iOS development", indexedChunks: chunks, topK: 3)
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.documentId, "swift-doc")
    }

    func testSearchRespectsTopK() {
        var allChunks: [IndexedChunk] = []
        for i in 0..<5 {
            allChunks += RAGService.indexDocument(id: "doc\(i)", name: "Doc \(i)", content: "Document about Swift programming language number \(i)")
        }
        let results = RAGService.searchDocuments(query: "Swift programming", indexedChunks: allChunks, topK: 2)
        XCTAssertLessThanOrEqual(results.count, 2)
    }

    func testSearchScoreDecreasing() {
        var allChunks: [IndexedChunk] = []
        allChunks += RAGService.indexDocument(id: "relevant", name: "Relevant", content: "Machine learning deep learning neural network training model")
        allChunks += RAGService.indexDocument(id: "unrelated", name: "Unrelated", content: "Cooking recipes for pasta and pizza in Italian restaurants")
        let results = RAGService.searchDocuments(query: "machine learning neural network", indexedChunks: allChunks, topK: 3)
        if results.count >= 2 {
            XCTAssertGreaterThanOrEqual(results[0].score, results[1].score)
        }
    }

    // MARK: - RAG Context

    func testBuildRAGContextNil() {
        let context = RAGService.buildRAGContext(query: "test", indexedChunks: [], topK: 3)
        XCTAssertNil(context)
    }

    func testBuildRAGContextFormat() {
        let chunks = RAGService.indexDocument(id: "doc1", name: "Test", content: "Apple uses Swift for iOS apps. Swift provides safety and performance.")
        let context = RAGService.buildRAGContext(query: "Swift iOS", indexedChunks: chunks, topK: 3)
        XCTAssertNotNil(context)
        if let ctx = context {
            XCTAssertTrue(ctx.contains("[Test#"))
        }
    }
}
