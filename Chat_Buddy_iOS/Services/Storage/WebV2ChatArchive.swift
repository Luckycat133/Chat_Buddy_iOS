import Foundation
import CoreFoundation

/// Read-only recovery from a Web v2 export. This does not create cloud actors,
/// conversations or messages, execute attachments, or alter the original file.
struct WebV2ChatArchive {
    struct Thread: Identifiable {
        let id: String
        let name: String
        let messages: [Message]
    }

    struct Message: Identifiable {
        let id: String
        let senderID: String
        let content: String
        let timestamp: String?
        let quotedMessageID: String?
        let attachmentIDs: [String]
    }

    let threads: [Thread]

    static let maxBytes = 50 * 1_024 * 1_024
    private static let maxRecordCount = 100_000
    private static let chatKey = "chat-buddy-chats"

    /// The public importer preflights the file length. Keep the boundary here
    /// too so a caller handing us Data cannot bypass it.
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maxBytes else { throw ArchiveError.tooLarge }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = root["_meta"] as? [String: Any],
              meta["app"] as? String == "Chat Buddy",
              let version = meta["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.doubleValue == 2 else {
            throw ArchiveError.unsupportedFormat
        }
        guard let local = root["localStorage"] as? [String: Any],
              let databases = (root["indexedDB"] ?? [:]) as? [String: Any],
              let mainDB = (databases["chat-buddy-main"] ?? [:]) as? [String: Any],
              let main = (mainDB["kv"] ?? []) as? [[String: Any]],
              main.count <= maxRecordCount else {
            throw ArchiveError.malformedChats
        }
        let records = main.filter { $0["key"] as? String == chatKey }
        guard records.count <= 1 else { throw ArchiveError.malformedChats }

        // Same priority as the Web startup hydrator: IndexedDB first, then
        // current localStorage and finally the pre-migration prefixed key.
        let raw: Any?
        if let primary = records.first {
            guard let value = primary["value"] else { throw ArchiveError.malformedChats }
            raw = value
        } else {
            raw = local[chatKey] ?? local["chat-buddy:\(chatKey)"]
        }
        guard let raw else { throw ArchiveError.noChats }
        let payload: Any
        if let text = raw as? String {
            payload = try JSONSerialization.jsonObject(with: Data(text.utf8))
        } else {
            payload = raw
        }
        guard let rows = payload as? [[String: Any]], rows.count <= maxRecordCount else {
            throw ArchiveError.malformedChats
        }

        var seenThreads = Set<String>()
        var messageCount = 0
        let threads = try rows.map { row in
            guard let id = row["id"] as? String, !id.isEmpty, seenThreads.insert(id).inserted,
                  let messageRows = (row["messages"] ?? []) as? [[String: Any]] else {
                throw ArchiveError.malformedChats
            }
            messageCount += messageRows.count
            guard messageCount <= maxRecordCount else { throw ArchiveError.tooLarge }
            var seenMessages = Set<String>()
            let messages = try messageRows.map { message in
                guard let messageID = message["id"] as? String, !messageID.isEmpty,
                      seenMessages.insert(messageID).inserted,
                      let sender = message["senderId"] as? String, !sender.isEmpty,
                      let content = message["content"] as? String,
                      message["timestamp"] == nil || message["timestamp"] is String,
                      message["quotedMessageId"] == nil || message["quotedMessageId"] is NSNull
                          || message["quotedMessageId"] is String else {
                    throw ArchiveError.malformedChats
                }
                return Message(id: messageID, senderID: sender, content: content,
                               timestamp: message["timestamp"] as? String,
                               quotedMessageID: message["quotedMessageId"] as? String,
                               attachmentIDs: message["attachmentIds"] as? [String] ?? [])
            }
            let name = (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            return Thread(id: id, name: name, messages: messages)
        }
        return Self(threads: threads)
    }

    enum ArchiveError: LocalizedError {
        case unsupportedFormat, malformedChats, noChats, tooLarge

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "Select a Chat Buddy Web v2 backup."
            case .malformedChats: "The archive's chat data is malformed; no data was changed."
            case .noChats: "This Web backup contains no local chat records."
            case .tooLarge: "The Web backup exceeds the local recovery limit."
            }
        }
    }
}
