import Foundation

/// Context compression service for long conversations.
/// Port of ContextCompressor.js — summarizes old messages and keeps recent ones intact.
enum ContextCompressor {

    /// Start compressing when total visible messages exceed this count.
    static let compressionThreshold = 15
    /// Number of most recent messages to keep untouched.
    static let recentWindow = 8

    struct CompressionResult {
        let compressed: Bool
        let summary: String?
        let recentMessages: [ChatMessage]
    }

    /// Compress a conversation by summarizing older messages and preserving recent ones.
    /// If message count <= threshold, returns the original messages unchanged.
    static func compress(messages: [ChatMessage], personas: [Persona]) -> CompressionResult {
        let visible = messages.filter { $0.role != .system && $0.role != .tool }
        guard visible.count > compressionThreshold else {
            return CompressionResult(compressed: false, summary: nil, recentMessages: visible)
        }

        let cutoff = visible.count - recentWindow
        let oldMessages = Array(visible.prefix(cutoff))
        let recentMessages = Array(visible.suffix(recentWindow))

        let participants = extractParticipants(from: oldMessages, personas: personas)
        let topics = extractTopics(from: oldMessages)

        let summary = "[Earlier conversation summary: \(oldMessages.count) messages between \(participants). Topics discussed: \(topics)]"

        return CompressionResult(compressed: true, summary: summary, recentMessages: recentMessages)
    }

    /// Build a compressed message array: a system-level summary + recent messages.
    static func compressedContext(messages: [ChatMessage], personas: [Persona]) -> [ChatMessage] {
        let result = compress(messages: messages, personas: personas)
        guard result.compressed, let summary = result.summary else {
            return messages.filter { $0.role != .system }
        }
        let summaryMsg = ChatMessage(role: .system, content: summary)
        return [summaryMsg] + result.recentMessages
    }

    // MARK: - Private

    private static func extractParticipants(from messages: [ChatMessage], personas: [Persona]) -> String {
        var names = Set<String>()
        for msg in messages {
            if msg.role == .user {
                names.insert("User")
            } else if let pid = msg.speakingPersonaId, let p = PersonaStore.persona(byId: pid) {
                names.insert(p.name)
            } else if msg.role == .assistant {
                if let first = personas.first { names.insert(first.name) }
            }
        }
        return names.sorted().joined(separator: ", ")
    }

    private static func extractTopics(from messages: [ChatMessage]) -> String {
        let allText = messages.map(\.content).joined(separator: " ")
        let commonWords: Set<String> = [
            "the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
            "her", "was", "one", "our", "out", "day", "get", "has", "him", "his",
            "how", "its", "let", "may", "new", "now", "old", "see", "way", "who",
            "did", "got", "use", "say", "she", "too", "any", "that", "with", "this",
            "will", "have", "from", "been", "just", "know", "like", "what", "when",
            "about", "them", "then", "would", "make", "some", "could", "also"
        ]
        let words = allText.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 5 && !commonWords.contains($0) }

        var freq: [String: Int] = [:]
        for w in words { freq[w, default: 0] += 1 }
        let top = freq.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        return top.isEmpty ? "general" : top.joined(separator: ", ")
    }
}
