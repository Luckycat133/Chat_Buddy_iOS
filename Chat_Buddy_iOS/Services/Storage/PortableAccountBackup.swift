import Foundation
import CryptoKit

/// Typed projection used to read threads and resolve attachments. The original
/// document is retained separately so unknown local fields and all bytes round-trip.
struct PortableAccountBackup {
    static let maxBytes = 4 * 1024 * 1024

    struct Attachment: Decodable, Identifiable {
        let id: String
        let name: String
        let mimeType: String
        let byteLength: Int
        let contentBase64: String?

        var verifiedInlineBytes: Data? {
            guard let contentBase64, let data = Data(base64Encoded: contentBase64),
                  data.count == byteLength, data.base64EncodedString() == contentBase64 else { return nil }
            return data
        }
    }

    struct Account: Decodable {
        let accountId: String
        let actorId: String
        let displayName: String
        let locale: String
        let timezone: String
        let conversations: [Conversation]
    }

    struct Conversation: Decodable, Identifiable {
        let id: String
        let publicName: String?
        let lastReadSequence: Int
        let messages: [Message]
    }

    struct Message: Decodable, Identifiable {
        let id: String
        let senderActorId: String
        let content: String
        let sequence: Int
        let replyToMessageId: String?
        let attachmentIds: [String]?
    }

    private struct Projection: Decodable {
        struct Metadata: Decodable {
            let app: String
            let version: Int
        }
        let _meta: Metadata
        let cloudAccount: Account?
        let attachments: [Attachment]?
    }

    let document: Data
    let account: Account?
    let attachments: [Attachment]
    let localChats: [WebV2ChatArchive.Thread]
    private let localImages: [String: Attachment]

    var sha256: String {
        SHA256.hash(data: document).map { String(format: "%02x", $0) }.joined()
    }

    func attachments(for message: WebV2ChatArchive.Message) -> [Attachment] {
        var references = message.attachmentIDs
        if message.content.hasPrefix("[IMG:"), message.content.hasSuffix("]") {
            references.append(String(message.content.dropFirst("[IMG:".count).dropLast()))
        }
        var seen = Set<String>()
        var output = references.filter { seen.insert($0).inserted }.enumerated().map { index, reference in
            localImages[reference] ?? Self.inlineImage(id: message.id + "-inline-" + String(index), encoded: reference)
                ?? Attachment(id: reference, name: "Image", mimeType: "application/octet-stream", byteLength: 0, contentBase64: nil)
        }
        if message.content.hasPrefix("[FILE]") {
            output.append(Attachment(id: message.id + "-file",
                                     name: String(message.content.dropFirst("[FILE]".count)).trimmingCharacters(in: .whitespaces),
                                     mimeType: "application/octet-stream", byteLength: 0, contentBase64: nil))
        }
        return output
    }

    private static func inlineImage(id: String, encoded: String) -> Attachment? {
        let parts = encoded.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let mimeType: String
        switch parts[0] {
        case "data:image/png;base64": mimeType = "image/png"
        case "data:image/jpeg;base64": mimeType = "image/jpeg"
        default: return nil
        }
        let base64 = String(parts[1])
        guard let bytes = Data(base64Encoded: base64), bytes.base64EncodedString() == base64 else { return nil }
        return Attachment(id: id, name: id, mimeType: mimeType, byteLength: bytes.count, contentBase64: base64)
    }


    init(document: Data) throws {
        guard document.count <= Self.maxBytes,
              String(data: document, encoding: .utf8) != nil else {
            throw BackupError.invalidDocument
        }
        let projection = try JSONDecoder().decode(Projection.self, from: document)
        guard projection._meta.app == "Chat Buddy", projection._meta.version == 2 else {
            throw BackupError.invalidDocument
        }
        let attachments = projection.attachments ?? []
        var ids = Set<String>()
        for attachment in attachments {
            guard ids.insert(attachment.id).inserted, attachment.byteLength >= 0,
                  attachment.contentBase64 == nil || attachment.verifiedInlineBytes != nil else {
                throw BackupError.invalidAttachment
            }
        }
        if let account = projection.cloudAccount {
            guard UUID(uuidString: account.accountId) != nil, UUID(uuidString: account.actorId) != nil,
                  Set(account.conversations.map(\.id)).count == account.conversations.count else {
                throw BackupError.invalidDocument
            }
            for conversation in account.conversations {
                guard Set(conversation.messages.map(\.id)).count == conversation.messages.count,
                      Set(conversation.messages.map(\.sequence)).count == conversation.messages.count,
                      conversation.messages.allSatisfy({ ($0.attachmentIds ?? []).allSatisfy(ids.contains) }) else {
                    throw BackupError.invalidAttachment
                }
            }
        }
        do {
            localChats = try WebV2ChatArchive.decode(document).threads
        } catch WebV2ChatArchive.ArchiveError.noChats {
            localChats = []
        }
        let json = try JSONSerialization.jsonObject(with: document) as? [String: Any]
        let indexed = json?["indexedDB"] as? [String: Any]
        let imagesDB = indexed?["chat-buddy-images"] as? [String: Any]
        let rows = imagesDB?["images"] as? [[String: Any]] ?? []
        var localImages = [String: Attachment]()
        for row in rows {
            guard let id = row["id"] as? String, let data = row["data"] as? String,
                  localImages[id] == nil else { throw BackupError.invalidAttachment }
            localImages[id] = Self.inlineImage(id: id, encoded: data)
                ?? Attachment(id: id, name: id, mimeType: "application/octet-stream", byteLength: 0, contentBase64: nil)
        }
        self.localImages = localImages
        self.document = document
        self.account = projection.cloudAccount
        self.attachments = attachments
    }

    enum BackupError: LocalizedError {
        case invalidDocument
        case invalidAttachment
        case transferMismatch

        var errorDescription: String? {
            switch self {
            case .invalidDocument: "Unsupported Web v2 backup."
            case .invalidAttachment: "The backup contains an invalid attachment or reference."
            case .transferMismatch: "The stored backup does not match this file."
            }
        }
    }
}

struct PortableAccountBackupService {
    let http: HTTPClient

    struct Receipt: Decodable {
        let sha256: String
        let updated: Bool
    }

    private struct Import: Encodable, Sendable {
        let document: String
    }

    func read(live: Bool) async throws -> PortableAccountBackup {
        let data = try await http.sendRaw(live ? Endpoints.portableLiveAccountBackup : Endpoints.portableAccountBackup)
        return try PortableAccountBackup(document: data)
    }

    func restore(_ backup: PortableAccountBackup) async throws -> Receipt {
        guard let document = String(data: backup.document, encoding: .utf8) else {
            throw PortableAccountBackup.BackupError.invalidDocument
        }
        let receipt: Receipt = try await http.send(Endpoints.portableAccountBackup, method: "PUT", body: Import(document: document))
        guard receipt.sha256 == backup.sha256 else { throw PortableAccountBackup.BackupError.transferMismatch }
        return receipt
    }
}
