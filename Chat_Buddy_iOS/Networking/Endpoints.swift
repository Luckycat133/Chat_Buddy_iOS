import Foundation

/// Type-safe endpoint descriptor consumed by `HTTPClient`.
///
/// Mirrors the server's `/v1/*` routes. Authorization is always required
/// unless `requiresAuth` is set to `false` (sign-in, dev-signin, magic-link).
public struct APIEndpoint: Sendable {
    public let path: String
    public let query: [String: String]
    public let idempotencyKey: String?
    public let requiresAuth: Bool

    public init(
        path: String,
        query: [String: String] = [:],
        idempotencyKey: String? = nil,
        requiresAuth: Bool = true,
    ) {
        self.path = path
        self.query = query
        self.idempotencyKey = idempotencyKey
        self.requiresAuth = requiresAuth
    }
}

/// Stable endpoint factory used by repositories.
///
/// All paths must match the server's `/v1/*` routes; mismatches will surface
/// as `APIError.notFound` and should be caught in repository-level tests.
public enum Endpoints {
    // MARK: Auth

    public static func devSignIn(displayName: String) -> APIEndpoint {
        APIEndpoint(
            path: "/v1/auth/dev-signin",
            query: ["displayName": displayName],
            requiresAuth: false,
        )
    }

    public static let refresh = APIEndpoint(path: "/v1/auth/refresh", requiresAuth: false)
    public static let logout = APIEndpoint(path: "/v1/auth/logout")

    // MARK: Onboarding

    public static let onboardingState = APIEndpoint(path: "/v1/onboarding")

    public static func advanceOnboarding() -> APIEndpoint {
        APIEndpoint(path: "/v1/onboarding/advance")
    }

    // MARK: Sync

    public static func sync(cursor: String?) -> APIEndpoint {
        APIEndpoint(
            path: "/v1/sync",
            query: cursor.map { ["cursor": $0] } ?? [:],
        )
    }

    // MARK: Actors

    public static let actors = APIEndpoint(path: "/v1/actors")

    public static func actor(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/actors/\(id)")
    }

    // MARK: Relationships

    public static let relationships = APIEndpoint(path: "/v1/relationships")

    /// Delete contact / block counterpart per DOMAIN_ARCHITECTURE §4.7
    /// states (requested|accepted|declined|deleted|blocked). REVERSIBLE
    /// ASSUMPTION: route shape mirrors friend-request decision; the server
    /// contract lists block under moderation but does not pin the route.
    public static func relationshipDecision(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/relationships/\(id)/decision")
    }

    // MARK: Conversations

    public static let conversations = APIEndpoint(path: "/v1/conversations")
    public static func conversation(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/conversations/\(id)")
    }
    public static func closeBurst(conversationId: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/conversations/\(conversationId)/bursts/close")
    }

    // MARK: Messages

    public static func messages(conversationId: String, cursor: Int?, limit: Int = 50) -> APIEndpoint {
        var q: [String: String] = ["limit": "\(limit)"]
        if let cursor = cursor { q["cursor"] = "\(cursor)" }
        return APIEndpoint(path: "/v1/conversations/\(conversationId)/messages", query: q)
    }

    public static func sendMessage(conversationId: String, idempotencyKey: String) -> APIEndpoint {
        APIEndpoint(
            path: "/v1/conversations/\(conversationId)/messages",
            idempotencyKey: idempotencyKey,
        )
    }

    // MARK: Friend requests

    public static let friendRequests = APIEndpoint(path: "/v1/friend-requests")

    public static func friendRequestDecision(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/friend-requests/\(id)/decision")
    }

    // MARK: Media

    /// Request a signed upload slot. REVERSIBLE ASSUMPTION: the contract
    /// says Moments media uploads via a signed URL; the concrete route is
    /// `/v1/media` returning `{ assetId, uploadUrl }`, then PUT bytes.
    public static let media = APIEndpoint(path: "/v1/media")

    // MARK: Group invitations

    public static func invitationDecision(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/invitations/\(id)/decision")
    }

    // MARK: Moments

    public static func moments(cursor: String? = nil, limit: Int? = nil) -> APIEndpoint {
        var q: [String: String] = [:]
        if let cursor { q["cursor"] = cursor }
        if let limit { q["limit"] = "\(limit)" }
        return APIEndpoint(path: "/v1/moments", query: q)
    }

    public static func momentInteraction(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/moments/\(id)/interactions")
    }

    /// Delete own post (skill §15 feed requirements). REVERSIBLE
    /// ASSUMPTION: DELETE on the moment resource.
    public static func momentDelete(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/moments/\(id)")
    }

    // MARK: Legacy import

    /// One-time normalized legacy import batch (skill §17). Never carries
    /// API credentials — see `LegacyImportPayloadBuilder`.
    public static let accountImport = APIEndpoint(path: "/v1/account/import")

    // MARK: Memory

    public static let memory = APIEndpoint(path: "/v1/memory")
    public static func memoryGrant(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/memory/\(id)/grant")
    }

    // MARK: Proactive

    public static let proactiveIntents = APIEndpoint(path: "/v1/proactive-intents")
    public static let proactiveDue = APIEndpoint(path: "/v1/proactive-intents/due")

    public static func proactiveCancel(id: String) -> APIEndpoint {
        APIEndpoint(path: "/v1/proactive-intents/\(id)/cancel")
    }

    // MARK: Capabilities

    public static let capabilityWeather = APIEndpoint(path: "/v1/capabilities/weather")
    public static let capabilitySearch = APIEndpoint(path: "/v1/capabilities/search")
    public static let capabilityCalendarPropose = APIEndpoint(
        path: "/v1/capabilities/calendar/propose",
    )
    public static let capabilityCalendarResult = APIEndpoint(
        path: "/v1/capabilities/calendar/result",
    )

    // MARK: Account

    public static let accountExport = APIEndpoint(path: "/v1/account/export")
    public static let accountDelete = APIEndpoint(path: "/v1/account/delete")

    // MARK: World events (for debug diagnostics only)

    public static let worldEvents = APIEndpoint(path: "/v1/world-events")
}