import Foundation
import SwiftData
import os

/// Repository actor that:
///   - Reads from SwiftData cache for offline rendering.
///   - Falls back to network fetch on miss; updates cache.
///   - Surfaces APIError unchanged so views can branch on stable codes.
///
/// Per skill §"API models and contract discipline":
///   - DTOs are decoded but not used as long-lived SwiftUI state.
///   - Mapping to cached models happens here.
public actor ActorRepository {
    private let http: HTTPClient
    private let context: ModelContext
    private let logger = CloudLogger.auth

    public init(http: HTTPClient, context: ModelContext) {
        self.http = http
        self.context = context
    }

    public func listActors() async throws -> [CachedActor] {
        // Cache-first: render immediately, refresh in background.
        let cached = await MainActor.run { () -> [CachedActor] in
            (try? self.context.fetch(FetchDescriptor<CachedActor>(
                sortBy: [SortDescriptor(\.publicName)]
            ))) ?? []
        }
        do {
            let remote = try await http.get(Endpoints.actors, as: ActorsListResponse.self)
            try await MainActor.run {
                for dto in remote.items {
                    Self.upsertActor(dto, in: self.context)
                }
                try? self.context.save()
            }
        } catch let error as APIError where error.code == .unauthorized {
            // Auth lost mid-session; surface so AppState can re-route.
            throw error
        } catch {
            logger.notice("actor list refresh failed: \(String(describing: error), privacy: .public)")
        }
        return cached
    }

    public func fetchActor(id: String) async throws -> CachedActor {
        let cached = await MainActor.run { () -> CachedActor? in
            (try? self.context.fetch(
                FetchDescriptor<CachedActor>(predicate: #Predicate { $0.id == id })
            ).first)
        }
        if let actor = cached {
            // Refresh in background; return cache for snappy UI.
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.refresh(actorId: id)
            }
            return actor
        }
        return try await refresh(actorId: id)
    }

    private func refresh(actorId: String) async throws -> CachedActor {
        let dto = try await http.get(
            Endpoints.actor(id: actorId),
            as: ActorDetailResponse.self,
        )
        try await MainActor.run {
            Self.upsertActor(dto.actor, in: self.context)
            try? self.context.save()
        }
        return CachedActor(
            id: dto.actor.id,
            socialGraphId: dto.actor.socialGraphId,
            type: dto.actor.type,
            publicName: dto.actor.publicName,
            avatarAssetId: dto.actor.avatarAssetId,
            templateId: dto.actor.templateId,
            status: dto.actor.status,
            updatedAt: Date(),
        )
    }

    @MainActor
    private static func upsertActor(_ dto: RemoteActorDTO, in context: ModelContext) {
        let existing = try? context.fetch(
            FetchDescriptor<CachedActor>(predicate: #Predicate { $0.id == dto.id })
        ).first
        if let existing {
            existing.socialGraphId = dto.socialGraphId
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

    private struct ActorsListResponse: Codable, Sendable {
        let items: [RemoteActorDTO]
    }

    private struct ActorDetailResponse: Codable, Sendable {
        let actor: RemoteActorDTO
    }
}