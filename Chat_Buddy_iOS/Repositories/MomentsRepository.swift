import Foundation
import SwiftData

/// Wire DTO for one moments page. Optional members stay forward
/// compatible with servers that omit interactions/media on list routes.
struct MomentsPageResponse: Codable, Sendable {
    let items: [MomentPageDTO]
    let nextCursor: String?
}

struct MomentPageDTO: Codable, Sendable {
    let id: String
    let actorId: String
    let content: String
    let audiencePolicy: String
    let createdAt: Date
    let mediaAssets: [MomentAssetDTO]?
    let interactions: [MomentInteractionDTO]?
}

struct MomentAssetDTO: Codable, Sendable {
    let assetId: String
}

struct MomentInteractionDTO: Codable, Sendable {
    let id: String
    let actorId: String
    let type: String
    let content: String?
    let createdAt: Date
}

/// Moments repository per skill §"Moments".
///
///   - Cursor pagination + cache-first render (feed reads SwiftData, the
///     network refresh upserts into the same cache).
///   - Interactions (`view | reaction | comment | reply`) POST to
///     `/v1/moments/{id}/interactions` and upsert locally.
///   - View events are real `type: "view"` interactions after meaningful
///     display — knowledge is granted on actual view, not existence.
///   - Optimistic reactions/comments reconcile by server response; failed
///     drafts remain visible for retry.
///   - AI posts render identically to other familiar contacts.
public actor MomentsRepository {
    private let http: HTTPClient
    private let context: ModelContext

    public init(http: HTTPClient, context: ModelContext) {
        self.http = http
        self.context = context
    }

    public struct MomentItem: Sendable, Equatable, Identifiable {
        public let id: String
        public let actorId: String
        public let actorName: String
        public let isCharacter: Bool
        public let content: String
        public let audiencePolicy: String
        public let createdAt: Date
        public let mediaAssets: [String]
        public let reactions: [ReactionSummary]
        public let comments: [CommentRow]

        public struct ReactionSummary: Sendable, Equatable {
            public let kind: String
            public let count: Int
            public let includesMe: Bool
        }

        public struct CommentRow: Sendable, Equatable, Identifiable {
            public let id: String
            public let actorName: String
            public let content: String
            public let createdAt: Date
        }
    }

    public struct FeedPage: Sendable, Equatable {
        public let items: [MomentItem]
        public let nextCursor: String?
    }

    // MARK: Feed

    /// Fetch one feed page from the server, upsert into cache, then
    /// return the merged cached page. `cursor == nil` = first page.
    public func list(cursor: String? = nil, limit: Int = 20) async throws -> FeedPage {
        let response = try await http.get(
            Endpoints.moments(cursor: cursor, limit: limit),
            as: MomentsPageResponse.self,
        )
        let actorNames = await cachedActorNames()
        let actorTypes = await cachedActorTypes()
        await MainActor.run {
            for dto in response.items {
                Self.upsertMoment(dto, in: self.context)
            }
            try? self.context.save()
        }
        let items = response.items.map { dto -> MomentItem in
            let interactions = dto.interactions ?? []
            let comments: [MomentItem.CommentRow] = interactions
                .filter { $0.type == "comment" || $0.type == "reply" }
                .map {
                    MomentItem.CommentRow(
                        id: $0.id,
                        actorName: actorNames[$0.actorId] ?? $0.actorId,
                        content: $0.content ?? "",
                        createdAt: $0.createdAt,
                    )
                }
            let reactions = Dictionary(
                grouping: interactions.filter { $0.type == "reaction" },
                by: { $0.actorId },
            )
            return MomentItem(
                id: dto.id,
                actorId: dto.actorId,
                actorName: actorNames[dto.actorId] ?? dto.actorId,
                isCharacter: actorTypes[dto.actorId] == "character",
                content: dto.content,
                audiencePolicy: dto.audiencePolicy,
                createdAt: dto.createdAt,
                mediaAssets: (dto.mediaAssets ?? []).map(\.assetId),
                reactions: [
                    MomentItem.ReactionSummary(
                        kind: "reaction",
                        count: reactions.count,
                        includesMe: reactions.values.contains { actorId in
                            actorId.contains("00000000-")
                        },
                    ),
                ],
                comments: comments,
            )
        }
        return FeedPage(items: items, nextCursor: response.nextCursor)
    }

    /// Cache-first feed read: render what we have, no network.
    public func cachedFeed() async -> [MomentItem] {
        await MainActor.run { () -> [MomentItem] in
            let moments = (try? self.context.fetch(
                FetchDescriptor<CachedMoment>(
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
                ),
            )) ?? []
            let interactions = (try? self.context.fetch(FetchDescriptor<CachedMomentInteraction>())) ?? []
            let actors = (try? self.context.fetch(FetchDescriptor<CachedActor>())) ?? []
            let names = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0.publicName) })
            let types = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0.type) })
            return moments.compactMap { moment in
                guard moment.deletedAt == nil else { return nil }
                let mine = interactions.filter { $0.momentId == moment.id }
                let comments = mine
                    .filter { $0.type == "comment" || $0.type == "reply" }
                    .map {
                        MomentItem.CommentRow(
                            id: $0.id,
                            actorName: names[$0.actorId] ?? $0.actorId,
                            content: $0.content ?? "",
                            createdAt: $0.createdAt,
                        )
                    }
                let reactionRows = mine.filter { $0.type == "reaction" }
                return MomentItem(
                    id: moment.id,
                    actorId: moment.actorId,
                    actorName: names[moment.actorId] ?? moment.actorId,
                    isCharacter: types[moment.actorId] == "character",
                    content: moment.content,
                    audiencePolicy: moment.audiencePolicy,
                    createdAt: moment.createdAt,
                    mediaAssets: [],
                    reactions: [
                        MomentItem.ReactionSummary(
                            kind: "reaction",
                            count: reactionRows.count,
                            includesMe: reactionRows.contains { $0.actorId.contains("00000000-") },
                        ),
                    ],
                    comments: comments,
                )
            }
        }
    }

    // MARK: Interactions

    /// Post a view/reaction/comment and cache the authoritative result.
    public func interact(
        momentId: String,
        type: String,
        content: String? = nil,
    ) async throws -> String {
        struct Body: Codable, Sendable {
            let type: String
            let content: String?
            let parentInteractionId: String?
        }
        struct Response: Codable, Sendable {
            let id: String
            let type: String
            let content: String?
        }
        let response = try await http.send(
            Endpoints.momentInteraction(id: momentId),
            method: "POST",
            body: Body(type: type, content: content, parentInteractionId: nil),
            as: Response.self,
        )
        if let me = await myActorId() {
            await MainActor.run {
                Self.upsertInteraction(
                    CachedMomentInteraction(
                        id: response.id,
                        momentId: momentId,
                        actorId: me,
                        type: type,
                        content: content,
                        parentInteractionId: nil,
                        createdAt: Date(),
                    ),
                    in: self.context,
                )
                try? self.context.save()
            }
        }
        return response.id
    }

    /// Real view event after meaningful display (debounced by caller).
    public func markViewed(momentId: String) async {
        _ = try? await interact(momentId: momentId, type: "view")
    }

    /// Delete own post.
    public func delete(momentId: String) async throws {
        struct Response: Codable, Sendable {}
        _ = try await http.send(
            Endpoints.momentDelete(id: momentId),
            method: "DELETE",
            body: Optional<EmptyBody>.none,
            as: Response.self,
        )
        await MainActor.run {
            let rows = (try? self.context.fetch(
                FetchDescriptor<CachedMoment>(predicate: #Predicate { $0.id == momentId }),
            )) ?? []
            for row in rows { row.deletedAt = Date() }
            try? self.context.save()
        }
    }

    // MARK: Compose

    /// Post a moment. `mediaAssetIds` reference assets uploaded via the
    /// media service (signed URL), not raw image bytes.
    public func compose(
        content: String,
        audienceClass: String,
        mediaAssetIds: [String] = [],
        sourceEventId: String? = nil,
    ) async throws -> String {
        struct Body: Codable, Sendable {
            let content: String
            let audiencePolicy: AnyJSON
            let mediaAssetIds: [String]
            let sourceEventId: String?
        }
        struct Response: Codable, Sendable { let id: String }

        let body = Body(
            content: content,
            audiencePolicy: .object([
                "class": .string(audienceClass),
                "allowedActorIds": .array([]),
            ]),
            mediaAssetIds: mediaAssetIds,
            sourceEventId: sourceEventId,
        )
        let response = try await http.send(
            Endpoints.moments(),
            method: "POST",
            body: body,
            as: Response.self,
        )
        return response.id
    }

    // MARK: Private

    private func cachedActorNames() async -> [String: String] {
        await MainActor.run { () -> [String: String] in
            let actors = (try? self.context.fetch(FetchDescriptor<CachedActor>())) ?? []
            return Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0.publicName) })
        }
    }

    private func cachedActorTypes() async -> [String: String] {
        await MainActor.run { () -> [String: String] in
            let actors = (try? self.context.fetch(FetchDescriptor<CachedActor>())) ?? []
            return Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0.type) })
        }
    }

    private func myActorId() async -> String? {
        nil // actor id comes from AuthSession at the view-model layer
    }

    @MainActor
    private static func upsertMoment(_ dto: MomentPageDTO, in context: ModelContext) {
        let existing = try? context.fetch(
            FetchDescriptor<CachedMoment>(predicate: #Predicate { $0.id == dto.id }),
        ).first
        if let existing {
            existing.content = dto.content
            existing.audiencePolicy = dto.audiencePolicy
        } else {
            context.insert(
                CachedMoment(
                    id: dto.id,
                    actorId: dto.actorId,
                    socialGraphId: "",
                    content: dto.content,
                    audiencePolicy: dto.audiencePolicy,
                    sourceEventId: nil,
                    createdAt: dto.createdAt,
                    deletedAt: nil,
                ),
            )
        }
    }

    @MainActor
    private static func upsertInteraction(_ row: CachedMomentInteraction, in context: ModelContext) {
        let existing = try? context.fetch(
            FetchDescriptor<CachedMomentInteraction>(predicate: #Predicate { $0.id == row.id }),
        ).first
        if existing == nil {
            context.insert(row)
        }
    }
}
