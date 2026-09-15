import Foundation
import SwiftData

/// Conversation and message repository per skill §"Chat UI" + §"Make
/// offline behavior explicit".
///
///   - Server is authoritative for sequence numbers and burst closure.
///   - Client sends individual messages immediately with stable
///     idempotency keys.
///   - Server collapses same-burst messages into one `MessageBurst`; the
///     UI may render them as separate rows but must NOT make AI decisions
///     locally.
///   - On re-entry, the client replays any unsent mutations from the
///     outbox; the server deduplicates by `(conversation_id,
///     client_idempotency_key)`.
public actor ConversationRepository {
    private let http: HTTPClient
    private let context: ModelContext
    private let outbox: OutboxStore
    private let accountIdProvider: @Sendable () async -> String?

    public init(
        http: HTTPClient,
        context: ModelContext,
        outbox: OutboxStore,
        accountIdProvider: @escaping @Sendable () async -> String?,
    ) {
        self.http = http
        self.context = context
        self.outbox = outbox
        self.accountIdProvider = accountIdProvider
    }

    /// Identifiable so SwiftUI `List`/`ForEach` can render rows directly.
    public struct ConversationListItem: Sendable, Equatable, Identifiable {
        public let id: String
        public let type: String
        public let publicName: String?
        public let unreadCount: Int
        public let lastMessagePreview: String?
    }

    public func listConversations() async throws -> [ConversationListItem] {
        struct Response: Codable, Sendable { let items: [Item] }
        struct Item: Codable, Sendable {
            let id: String
            let type: String
            let publicName: String?
            let unreadCount: Int?
            let lastMessagePreview: String?
        }
        let response = try await http.get(Endpoints.conversations, as: Response.self)
        return response.items.map {
            ConversationListItem(
                id: $0.id,
                type: $0.type,
                publicName: $0.publicName,
                unreadCount: $0.unreadCount ?? 0,
                lastMessagePreview: $0.lastMessagePreview,
            )
        }
    }

    public func listMessages(conversationId: String, cursor: Int? = nil) async throws -> [RemoteMessageDTO] {
        struct Response: Codable, Sendable { let items: [RemoteMessageDTO] }
        let response = try await http.get(
            Endpoints.messages(conversationId: conversationId, cursor: cursor, limit: 50),
            as: Response.self,
        )
        return response.items
    }

    public struct SendResult: Sendable, Equatable {
        public let accepted: Bool
        public let conflict: Bool
        public let messageId: String?
        public let sequence: Int?
    }

    /// Send a message. Always writes the outbox row first so an immediate
    /// `accepted` failure does not lose the user's text. The OutboxStore
    /// persists across launches.
    public func sendMessage(
        conversationId: String,
        content: String,
        replyToMessageId: String? = nil,
    ) async throws -> SendResult {
        let idempotencyKey = UUID().uuidString
        let payload = SendMessageBody(
            clientIdempotencyKey: idempotencyKey,
            content: content,
            replyToMessageId: replyToMessageId,
        )
        let body = try JSONEncoder().encode(payload)
        guard let accountId = await accountIdProvider() else {
            throw APIError(
                code: .unauthorized,
                message: "missing account id",
                status: 401,
                requestId: nil,
                details: nil,
            )
        }
        try await MainActor.run {
            try self.outbox.enqueue(
                accountId: accountId,
                method: "POST",
                path: "/v1/conversations/\(conversationId)/messages",
                idempotencyKey: idempotencyKey,
                body: body,
            )
        }
        return try await flushOne(
            accountId: accountId,
            idempotencyKey: idempotencyKey,
        )
    }

    public func flushOutbox() async throws -> [SendResult] {
        guard let accountId = await accountIdProvider() else { return [] }
        let pending = await MainActor.run { outbox.loadPending(accountId: accountId) }
        var results: [SendResult] = []
        for entry in pending {
            let result = try await flushOne(
                accountId: accountId,
                idempotencyKey: entry.idempotencyKey,
            )
            results.append(result)
        }
        return results
    }

    public func closeBurst(conversationId: String) async throws {
        struct Empty: Codable {}
        struct Response: Codable, Sendable { let closed: String? }
        _ = try await http.send(
            Endpoints.closeBurst(conversationId: conversationId),
            method: "POST",
            body: Optional<Empty>.none,
            as: Response.self,
        )
    }

    private func flushOne(accountId: String, idempotencyKey: String) async throws -> SendResult {
        guard let entry = await MainActor.run({
            self.outbox.loadPending(accountId: accountId).first(where: { $0.idempotencyKey == idempotencyKey })
        }) else {
            return SendResult(accepted: false, conflict: false, messageId: nil, sequence: nil)
        }
        await MainActor.run { self.outbox.markSending(id: entry.id) }
        do {
            struct Response: Codable, Sendable {
                let id: String
                let sequence: Int
            }
            let body = entry.bodyData
            let endpoint = Endpoints.sendMessage(
                conversationId: extractConversationId(from: entry.path),
                idempotencyKey: entry.idempotencyKey,
            )
            let response = try await http.send(
                endpoint,
                method: entry.method,
                body: body,
                as: Response.self,
            )
            await MainActor.run { self.outbox.markAccepted(id: entry.id) }
            return SendResult(
                accepted: true,
                conflict: false,
                messageId: response.id,
                sequence: response.sequence,
            )
        } catch let error as APIError where error.isConflict {
            await MainActor.run { self.outbox.markConflict(id: entry.id) }
            return SendResult(accepted: false, conflict: true, messageId: nil, sequence: nil)
        } catch {
            await MainActor.run {
                self.outbox.markFailed(id: entry.id, error: String(describing: error))
            }
            throw error
        }
    }

    private func extractConversationId(from path: String) -> String {
        // /v1/conversations/{conversationId}/messages
        let parts = path.split(separator: "/")
        guard let idx = parts.firstIndex(of: "conversations"),
              idx + 1 < parts.count else {
            return ""
        }
        return String(parts[idx + 1])
    }
}

private struct SendMessageBody: Codable {
    let clientIdempotencyKey: String
    let content: String
    let replyToMessageId: String?
}