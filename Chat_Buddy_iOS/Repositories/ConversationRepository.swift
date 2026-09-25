import Foundation
import SwiftData
import os

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
    private let logger = CloudLogger.sync

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
        public let lastActivityAt: Date?

        public init(
            id: String,
            type: String,
            publicName: String?,
            unreadCount: Int,
            lastMessagePreview: String?,
            lastActivityAt: Date?,
        ) {
            self.id = id
            self.type = type
            self.publicName = publicName
            self.unreadCount = unreadCount
            self.lastMessagePreview = lastMessagePreview
            self.lastActivityAt = lastActivityAt
        }
    }

    public func listConversations() async throws -> [ConversationListItem] {
        struct Response: Codable, Sendable { let items: [Item] }
        struct Item: Codable, Sendable {
            let id: String
            let type: String
            let publicName: String?
            let unreadCount: Int?
            let lastMessagePreview: String?
            let createdAt: Date
        }
        let response = try await http.get(Endpoints.conversations, as: Response.self)
        return response.items.map {
            ConversationListItem(
                id: $0.id,
                type: $0.type,
                publicName: $0.publicName,
                unreadCount: $0.unreadCount ?? 0,
                lastMessagePreview: $0.lastMessagePreview,
                lastActivityAt: $0.createdAt,
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

    // MARK: Cache-first reads (offline rendering)

    /// Render the chats list from the SwiftData cache without any network
    /// call. Delta sync (runSync) refreshes the same rows.
    public func cachedConversationList() async -> [ConversationListItem] {
        await MainActor.run { () -> [ConversationListItem] in
            let tombstones = (try? self.context.fetch(
                FetchDescriptor<CachedTombstone>(
                    predicate: #Predicate { $0.table == "conversations" },
                ),
            ))?.map(\.rowId) ?? []
            let tombstoneSet = Set(tombstones)
            let conversations = (try? self.context.fetch(
                FetchDescriptor<CachedConversation>(
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
                ),
            )) ?? []
            let messages = (try? self.context.fetch(FetchDescriptor<CachedMessage>())) ?? []
            let members = (try? self.context.fetch(FetchDescriptor<CachedConversationMember>())) ?? []
            let actors = (try? self.context.fetch(FetchDescriptor<CachedActor>())) ?? []
            let actorNames = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0.publicName) })

            var items: [ConversationListItem] = []
            for conversation in conversations where !tombstoneSet.contains(conversation.id) {
                let convMessages = messages
                    .filter { $0.conversationId == conversation.id && $0.deletedAt == nil }
                    .sorted { $0.sequence < $1.sequence }
                guard let last = convMessages.last else { continue }
                let myRead = members
                    .first { $0.conversationId == conversation.id }
                    .map(\.lastReadSequence) ?? 0
                let unread = convMessages.filter { $0.sequence > myRead }.count
                let title: String?
                if conversation.type == "group" {
                    title = conversation.publicName
                } else if conversation.type == "hidden_ai_direct" {
                    continue // never cached, never listed
                } else {
                    title = actorNames[last.senderActorId]
                        ?? conversation.publicName
                }
                items.append(
                    ConversationListItem(
                        id: conversation.id,
                        type: conversation.type,
                        publicName: title,
                        unreadCount: unread,
                        lastMessagePreview: last.content,
                        lastActivityAt: last.createdAt,
                    ),
                )
            }
            return items
        }
    }

    /// Cached messages for a conversation, oldest first, tombstoned rows
    /// removed. Renders instantly; network refresh replaces content.
    public func cachedMessages(conversationId: String) async -> [RemoteMessageDTO] {
        await MainActor.run { () -> [RemoteMessageDTO] in
            let rows = (try? self.context.fetch(
                FetchDescriptor<CachedMessage>(
                    predicate: #Predicate { $0.conversationId == conversationId },
                    sortBy: [SortDescriptor(\.sequence)],
                ),
            )) ?? []
            return rows.filter { $0.deletedAt == nil }.map { row in
                RemoteMessageDTO(
                    id: row.id,
                    conversationId: row.conversationId,
                    senderActorId: row.senderActorId,
                    sequence: row.sequence,
                    clientIdempotencyKey: row.clientIdempotencyKey,
                    kind: row.kind,
                    content: row.content,
                    structuredPayload: row.structuredPayload,
                    replyToMessageId: row.replyToMessageId,
                    burstId: row.burstId,
                    status: row.status,
                    createdAt: row.createdAt,
                    editedAt: row.editedAt,
                    deletedAt: row.deletedAt,
                )
            }
        }
    }

    /// Local mark-read: advance the member's lastReadSequence so the
    /// unread badge clears. Server truth still comes from sync; this is
    /// presentation-only state.
    public func markReadLocally(conversationId: String) async {
        await MainActor.run {
            let members = (try? self.context.fetch(
                FetchDescriptor<CachedConversationMember>(
                    predicate: #Predicate { $0.conversationId == conversationId },
                ),
            )) ?? []
            let latest = (try? self.context.fetch(
                FetchDescriptor<CachedMessage>(
                    predicate: #Predicate { $0.conversationId == conversationId },
                    sortBy: [SortDescriptor(\.sequence, order: .reverse)],
                ),
            ))?.first?.sequence
            guard let latest, latest > 0 else { return }
            for member in members where member.lastReadSequence < latest {
                member.lastReadSequence = latest
            }
            try? self.context.save()
        }
    }

    // MARK: Onboarding hydration (sync-flow entry)

    /// Cache-side read cursor mirroring the server's unread badge: the
    /// member row anchors unread computation in `cachedConversationList`,
    /// so `serverUnreadCount` messages after the last read one are kept.
    /// Static + pure for unit testing.
    static func readThroughSequence(maxMessageSequence: Int, serverUnreadCount: Int) -> Int {
        max(0, maxMessageSequence - max(0, serverUnreadCount))
    }

    /// Persist the onboarding conversation into the sync-backed cache
    /// from the REST reads the onboarding flow already performs.
    ///
    /// The server creates the Mira conversation during onboarding without
    /// emitting `world_events` for it, so `/v1/sync` returns empty
    /// upserts for a brand-new account and the cache-first Chats list
    /// stays empty. Rows are applied through `EventApplier` — identical
    /// tables, identity, and idempotency as a real sync envelope — so a
    /// later authoritative replay is a no-op and pending outbox
    /// mutations are untouched.
    public func hydrateOnboardingConversation(
        summary: ConversationListItem,
        messages: [RemoteMessageDTO],
        myActorId: String,
    ) async {
        let live = messages.filter { $0.deletedAt == nil }
        let member = RemoteConversationMemberDTO(
            id: nil,
            conversationId: summary.id,
            actorId: myActorId,
            status: "active",
            role: "member",
            invitedByActorId: nil,
            joinedAt: nil,
            leftAt: nil,
            lastReadSequence: Self.readThroughSequence(
                maxMessageSequence: live.map(\.sequence).max() ?? 0,
                serverUnreadCount: summary.unreadCount,
            ),
        )
        // The REST list row omits sync-only columns (social graph,
        // creator); synthesized placeholders stand in until the next
        // authoritative sync upsert fills them.
        let conversation = RemoteConversationDTO(
            id: summary.id,
            socialGraphId: "",
            type: summary.type,
            publicName: summary.publicName,
            createdByActorId: "",
            status: "active",
            createdAt: live.map(\.createdAt).min() ?? Date(),
        )
        do {
            try await MainActor.run {
                try EventApplier.hydrateOnboardingRows(
                    conversation: conversation,
                    messages: messages,
                    members: [member],
                    in: self.context,
                )
            }
        } catch {
            logger.notice(
                "onboarding cache hydration failed: \(String(describing: error), privacy: .public)",
            )
        }
    }

    // MARK: Group creation (skill §13)

    /// Create the group conversation shell. The group is not active until
    /// every invited actor confirms via `/v1/invitations/{id}/decision`.
    public struct CreateGroupResult: Sendable, Equatable {
        public let conversationId: String
        public let status: String
    }

    public func createGroup(
        name: String?,
        purpose: String?,
    ) async throws -> CreateGroupResult {
        struct Body: Codable, Sendable {
            let type: String
            let publicName: String?
            let purpose: String?
        }
        struct Response: Codable, Sendable {
            let id: String
            let status: String
        }
        let response = try await http.send(
            Endpoints.conversations,
            method: "POST",
            body: Body(type: "group", publicName: name, purpose: purpose),
            as: Response.self,
        )
        return CreateGroupResult(conversationId: response.id, status: response.status)
    }

    /// Invite one actor. Every invitee (human or AI) confirms.
    public func invite(conversationId: String, inviteeActorId: String) async throws -> String {
        struct Body: Codable, Sendable { let inviteeActorId: String }
        struct Response: Codable, Sendable { let id: String }
        let response = try await http.send(
            APIEndpoint(path: "/v1/conversations/\(conversationId)/invitations"),
            method: "POST",
            body: Body(inviteeActorId: inviteeActorId),
            as: Response.self,
        )
        return response.id
    }

    /// Accept or decline a group invitation addressed to me.
    public func decideInvitation(id: String, accept: Bool) async throws -> String {
        struct Body: Codable, Sendable { let accept: Bool }
        struct Response: Codable, Sendable { let id: String; let status: String }
        let response = try await http.send(
            Endpoints.invitationDecision(id: id),
            method: "POST",
            body: Body(accept: accept),
            as: Response.self,
        )
        return response.status
    }

    /// Cached group invitations for the pending-decisions step.
    public struct InvitationRow: Sendable, Equatable, Identifiable {
        public let id: String
        public let conversationId: String
        public let inviteeActorId: String
        public let inviteeName: String
        public let status: String
    }

    public func cachedInvitations(conversationId: String) async -> [InvitationRow] {
        await MainActor.run { () -> [InvitationRow] in
            let invitations = (try? self.context.fetch(
                FetchDescriptor<CachedGroupInvitation>(
                    predicate: #Predicate { $0.conversationId == conversationId },
                ),
            )) ?? []
            let actors = (try? self.context.fetch(FetchDescriptor<CachedActor>())) ?? []
            let names = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0.publicName) })
            return invitations.map {
                InvitationRow(
                    id: $0.id,
                    conversationId: $0.conversationId,
                    inviteeActorId: $0.inviteeActorId,
                    inviteeName: names[$0.inviteeActorId] ?? $0.inviteeActorId,
                    status: $0.status,
                )
            }
        }
    }

    /// Cached conversation row (for wizard step 6 / open group check).
    public func cachedConversation(id: String) async -> CachedConversationSnapshot? {
        await MainActor.run { () -> CachedConversationSnapshot? in
            let row = (try? self.context.fetch(
                FetchDescriptor<CachedConversation>(predicate: #Predicate { $0.id == id }),
            ))?.first
            guard let row else { return nil }
            let members = (try? self.context.fetch(
                FetchDescriptor<CachedConversationMember>(
                    predicate: #Predicate { $0.conversationId == id },
                ),
            )) ?? []
            return CachedConversationSnapshot(
                id: row.id,
                type: row.type,
                publicName: row.publicName,
                status: row.status,
                memberCount: members.filter { $0.status == "active" }.count,
                deletedAt: nil,
            )
        }
    }

    public struct SendResult: Sendable, Equatable {
        public let accepted: Bool
        public let conflict: Bool
        public let messageId: String?
        public let sequence: Int?
    }

    /// Enqueue only: persist the outbox row so the optimistic bubble
    /// renders as `queued` while the network round-trip happens. The
    /// caller then flushes by idempotency key.
    public func enqueueMessage(
        conversationId: String,
        content: String,
        replyToMessageId: String? = nil,
    ) async throws -> String {
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
        return idempotencyKey
    }

    /// Send a message. Always writes the outbox row first so an immediate
    /// `accepted` failure does not lose the user's text. The OutboxStore
    /// persists across launches.
    public func sendMessage(
        conversationId: String,
        content: String,
        replyToMessageId: String? = nil,
    ) async throws -> SendResult {
        let idempotencyKey = try await enqueueMessage(
            conversationId: conversationId,
            content: content,
            replyToMessageId: replyToMessageId,
        )
        guard let accountId = await accountIdProvider() else {
            throw APIError(
                code: .unauthorized,
                message: "missing account id",
                status: 401,
                requestId: nil,
                details: nil,
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

    /// Flush one pending outbox mutation by idempotency key (retry path).
    public func flushOne(idempotencyKey: String) async throws -> SendResult {
        guard let accountId = await accountIdProvider() else {
            throw APIError(
                code: .unauthorized,
                message: "missing account id",
                status: 401,
                requestId: nil,
                details: nil,
            )
        }
        return try await flushOne(accountId: accountId, idempotencyKey: idempotencyKey)
    }

    private func flushOne(accountId: String, idempotencyKey: String) async throws -> SendResult {
        let entry = await MainActor.run { () -> OutboxStore.Mutation? in
            self.outbox.loadPending(accountId: accountId).first(where: { $0.idempotencyKey == idempotencyKey })
        }
        guard let entry = entry else {
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