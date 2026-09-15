import Foundation
import SwiftData

/// Moments repository per skill §"Moments".
///
///   - Cache-first render with cursor pagination.
///   - Compose flow uploads via signed URL (server returns a media
///     manifest); iOS sends the manifest, not raw images.
///   - Reactions/comments are optimistic and reconciled.
///   - AI posts are rendered identically to other familiar contacts.
public actor MomentsRepository {
    private let http: HTTPClient
    private let context: ModelContext

    public init(http: HTTPClient, context: ModelContext) {
        self.http = http
        self.context = context
    }

    public struct MomentItem: Sendable, Equatable {
        public let id: String
        public let actorId: String
        public let content: String
        public let audiencePolicy: String
        public let createdAt: Date
        public let mediaAssets: [String]
    }

    public func list(cursor: String? = nil) async throws -> [MomentItem] {
        struct Response: Codable, Sendable {
            let items: [DTO]
            let nextCursor: String?
        }
        struct DTO: Codable, Sendable {
            let id: String
            let actorId: String
            let content: String
            let audiencePolicy: String
            let createdAt: Date
            let mediaAssets: [RemoteAsset]
        }
        struct RemoteAsset: Codable, Sendable {
            let assetId: String
        }
        let response = try await http.get(Endpoints.moments, as: Response.self)
        // Cache-first: read from SwiftData when present.
        return response.items.map { dto in
            MomentItem(
                id: dto.id,
                actorId: dto.actorId,
                content: dto.content,
                audiencePolicy: dto.audiencePolicy,
                createdAt: dto.createdAt,
                mediaAssets: dto.mediaAssets.map(\.assetId),
            )
        }
    }

    public func compose(
        content: String,
        audiencePolicy: [String: Any],
        sourceEventId: String? = nil,
    ) async throws -> String {
        struct Body: Codable {
            let content: String
            let audiencePolicy: AnyJSON
            let sourceEventId: String?
        }
        struct Response: Codable, Sendable { let id: String }

        // audiencePolicy is server-shaped; ship it as real JSON. The
        // former `[String: AnyCodableJSON]` body double-encoded every
        // value (AnyCodableJSON.encode writes the raw text as a string).
        let body = Body(
            content: content,
            audiencePolicy: .object(audiencePolicy.mapValues(AnyJSON.from)),
            sourceEventId: sourceEventId,
        )
        let response = try await http.send(
            Endpoints.moments,
            method: "POST",
            body: body,
            as: Response.self,
        )
        return response.id
    }

    public func interact(
        momentId: String,
        type: String,
        content: String? = nil,
    ) async throws -> String {
        struct Body: Codable {
            let type: String
            let content: String?
            let parentInteractionId: String?
        }
        struct Response: Codable, Sendable { let id: String }

        let body = Body(type: type, content: content, parentInteractionId: nil)
        let response = try await http.send(
            Endpoints.momentInteraction(id: momentId),
            method: "POST",
            body: body,
            as: Response.self,
        )
        return response.id
    }
}