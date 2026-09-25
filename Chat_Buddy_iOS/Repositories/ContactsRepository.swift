import Foundation
import SwiftData

/// Contacts and requests repository per skill §"Contacts and requests".
///
///   - Cache-first reads of actors / friend requests / relationships.
///   - Actions: send request, accept/decline, delete contact, block.
///   - AI request decisions arrive asynchronously through sync — the UI
///     renders `pending` and later outcomes; nothing is decided locally.
public actor ContactsRepository {
    private let http: HTTPClient
    private let context: ModelContext

    public init(http: HTTPClient, context: ModelContext) {
        self.http = http
        self.context = context
    }

    // MARK: Cache projection

    public func cachedProjection(myActorId: String) async -> ContactsProjection {
        await MainActor.run { () -> ContactsProjection in
            let requests = (try? self.context.fetch(FetchDescriptor<CachedFriendRequest>())) ?? []
            let relationships = (try? self.context.fetch(FetchDescriptor<CachedRelationship>())) ?? []
            let actors = (try? self.context.fetch(FetchDescriptor<CachedActor>())) ?? []
            let conversations = (try? self.context.fetch(FetchDescriptor<CachedConversation>())) ?? []
            let members = (try? self.context.fetch(FetchDescriptor<CachedConversationMember>())) ?? []

            let actorBriefs = Dictionary(
                uniqueKeysWithValues: actors.map {
                    ($0.id, ActorBrief(publicName: $0.publicName, isCharacter: $0.type == "character"))
                },
            )
            let memberCounts = Dictionary(
                grouping: members.filter { $0.status == "active" },
                by: { $0.conversationId },
            ).mapValues(\.count)

            return ContactsClassifier.project(
                requests: requests.map {
                    CachedFriendRequestSnapshot(
                        id: $0.id,
                        senderActorId: $0.senderActorId,
                        recipientActorId: $0.recipientActorId,
                        status: $0.status,
                        note: $0.note,
                        decidedAt: nil,
                    )
                },
                relationships: relationships.map {
                    CachedRelationshipSnapshot(
                        id: $0.id,
                        actorAId: $0.actorAId,
                        actorBId: $0.actorBId,
                        state: $0.state,
                        updatedAt: $0.updatedAt,
                    )
                },
                actors: actorBriefs,
                myActorId: myActorId,
                conversations: conversations.map {
                    CachedConversationSnapshot(
                        id: $0.id,
                        type: $0.type,
                        publicName: $0.publicName,
                        status: $0.status,
                        memberCount: memberCounts[$0.id] ?? 0,
                        deletedAt: nil,
                    )
                },
            )
        }
    }

    // MARK: Refresh

    public func refresh(myActorId _: String) async throws {
        // The actor list is mandatory: without the server pull the
        // projection is cache-only and newly-created counterparts have no
        // name or role. Request/relationship failures are accumulated but
        // do not prevent the other surfaces from merging.
        let actors = try await http.get(Endpoints.actors, as: ActorListResponse.self)
        await MainActor.run {
            for dto in actors.items {
                Self.upsertActor(dto, in: self.context)
            }
            try self.context.save()
        }

        var firstError: Error?
        do {
            let requests = try await http.get(
                Endpoints.friendRequests,
                as: FriendRequestListResponse.self,
            )
            await MainActor.run {
                for dto in requests.items {
                    Self.upsertRequest(dto, in: self.context)
                }
                try self.context.save()
            }
        } catch {
            firstError = error
        }
        do {
            let relationships = try await http.get(
                Endpoints.relationships,
                as: RelationshipListResponse.self,
            )
            await MainActor.run {
                for dto in relationships.items {
                    Self.upsertRelationship(dto, in: self.context)
                }
                try self.context.save()
            }
        } catch {
            firstError = firstError ?? error
        }
        if let firstError { throw firstError }
    }

    // MARK: Actions

    /// Send a friend request to a character or human. The recipient
    /// (or the server runtime, for AI) decides later.
    public func sendFriendRequest(toActorId: String, note: String?) async throws -> String {
        struct Body: Codable, Sendable {
            let recipientActorId: String
            let note: String?
        }
        struct Response: Codable, Sendable { let id: String; let status: String }
        let response = try await http.send(
            Endpoints.friendRequests,
            method: "POST",
            body: Body(recipientActorId: toActorId, note: note),
            as: Response.self,
        )
        return response.status
    }

    /// Accept or decline an inbound request. AI decisions are also
    /// server-side; this call is only for requests addressed to me.
    public func decide(requestId: String, accept: Bool) async throws -> String {
        struct Body: Codable, Sendable { let accept: Bool }
        struct Response: Codable, Sendable { let id: String; let status: String }
        let response = try await http.send(
            Endpoints.friendRequestDecision(id: requestId),
            method: "POST",
            body: Body(accept: accept),
            as: Response.self,
        )
        return response.status
    }

    /// Delete contact (preserves history) or block (stops contact).
    /// The UI must explain the difference; the server owns the state.
    public enum RelationshipAction: String, Sendable {
        case delete
        case block
        case unblock
    }

    public func mutateRelationship(relationshipId: String, action: RelationshipAction) async throws {
        struct Body: Codable, Sendable { let action: String }
        struct Response: Codable, Sendable { let id: String; let state: String }
        _ = try await http.send(
            Endpoints.relationshipDecision(id: relationshipId),
            method: "POST",
            body: Body(action: action.rawValue),
            as: Response.self,
        )
    }

    /// Set the private remark (only I can see it; the public identity is
    /// fixed per settled product decision 12).
    public func setPrivateRemark(relationshipId: String, remark: String) async throws {
        struct Body: Codable, Sendable { let privateRemark: String }
        struct Response: Codable, Sendable { let id: String }
        _ = try await http.send(
            APIEndpoint(path: "/v1/relationships/\(relationshipId)/preference"),
            method: "PATCH",
            body: Body(privateRemark: remark),
            as: Response.self,
        )
    }

    // MARK: Upserts

    @MainActor
    private static func upsertActor(_ dto: RemoteActorDTO, in context: ModelContext) {
        let existing = try? context.fetch(
            FetchDescriptor<CachedActor>(predicate: #Predicate { $0.id == dto.id }),
        ).first
        if let existing {
            if !dto.socialGraphId.isEmpty {
                existing.socialGraphId = dto.socialGraphId
            }
            existing.type = dto.type
            existing.publicName = dto.publicName
            existing.avatarAssetId = dto.avatarAssetId
            existing.templateId = dto.templateId
            existing.status = dto.status
            existing.updatedAt = Date()
        } else {
            context.insert(
                CachedActor(
                    id: dto.id,
                    socialGraphId: dto.socialGraphId,
                    type: dto.type,
                    publicName: dto.publicName,
                    avatarAssetId: dto.avatarAssetId,
                    templateId: dto.templateId,
                    status: dto.status,
                    updatedAt: Date(),
                ),
            )
        }
    }

    @MainActor
    private static func upsertRequest(_ dto: RemoteFriendRequestDTO, in context: ModelContext) {
        let existing = try? context.fetch(
            FetchDescriptor<CachedFriendRequest>(predicate: #Predicate { $0.id == dto.id }),
        ).first
        if let existing {
            existing.status = dto.status
            existing.note = dto.note
        } else {
            context.insert(
                CachedFriendRequest(
                    id: dto.id,
                    senderActorId: dto.senderActorId,
                    recipientActorId: dto.recipientActorId,
                    status: dto.status,
                    note: dto.note,
                    createdAt: dto.createdAt,
                ),
            )
        }
    }

    @MainActor
    private static func upsertRelationship(_ dto: RemoteRelationshipDTO, in context: ModelContext) {
        let existing = try? context.fetch(
            FetchDescriptor<CachedRelationship>(predicate: #Predicate { $0.id == dto.id }),
        ).first
        if let existing {
            existing.state = dto.state
            existing.updatedAt = dto.updatedAt
        } else {
            context.insert(
                CachedRelationship(
                    id: dto.id,
                    actorAId: dto.actorAId,
                    actorBId: dto.actorBId,
                    state: dto.state,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt,
                ),
            )
        }
    }

    private struct ActorListResponse: Codable, Sendable {
        let items: [RemoteActorDTO]
    }

    private struct FriendRequestListResponse: Codable, Sendable {
        let items: [RemoteFriendRequestDTO]
    }

    private struct RelationshipListResponse: Codable, Sendable {
        let items: [RemoteRelationshipDTO]
    }
}
