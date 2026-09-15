import Foundation

/// Stable, machine-readable error codes mirroring the server envelope
/// (`shared/contracts/errors.ts`).
///
/// Per the skill §"Settled product decisions":
///   - Server is authoritative. Client surfaces errors by stable code, not
///     by parsing English text.
public enum APIErrorCode: String, Codable, Sendable, Equatable {
    case unauthorized = "UNAUTHORIZED"
    case forbidden = "FORBIDDEN"
    case notFound = "NOT_FOUND"
    case conflict = "CONFLICT"
    case validationFailed = "VALIDATION_FAILED"
    case rateLimited = "RATE_LIMITED"
    case groupInvitationRequired = "GROUP_INVITATION_REQUIRED"
    case actorBlocked = "ACTOR_BLOCKED"
    case quietHours = "QUIET_HOURS"
    case proactiveExpired = "PROACTIVE_EXPIRED"
    case modelFailure = "MODEL_FAILURE"
    case toolFailure = "TOOL_FAILURE"
    case internal_ = "INTERNAL"

    /// Unknown / newer server codes fall back to a typed "other".
    case other

    /// Non-failable raw-value init: maps unknown server codes to `.other`
    /// instead of failing decode. Must switch explicitly — calling
    /// `APIErrorCode(rawValue:)` here would recurse into itself and stack
    /// overflow on the first server error envelope (CloudClientTests
    /// `testAPIErrorCodeMapsUnknownServerCodeToOther` locks this).
    public init(rawValue: String) {
        switch rawValue {
        case "UNAUTHORIZED": self = .unauthorized
        case "FORBIDDEN": self = .forbidden
        case "NOT_FOUND": self = .notFound
        case "CONFLICT": self = .conflict
        case "VALIDATION_FAILED": self = .validationFailed
        case "RATE_LIMITED": self = .rateLimited
        case "GROUP_INVITATION_REQUIRED": self = .groupInvitationRequired
        case "ACTOR_BLOCKED": self = .actorBlocked
        case "QUIET_HOURS": self = .quietHours
        case "PROACTIVE_EXPIRED": self = .proactiveExpired
        case "MODEL_FAILURE": self = .modelFailure
        case "TOOL_FAILURE": self = .toolFailure
        case "INTERNAL": self = .internal_
        default: self = .other
        }
    }
}

/// Standard envelope per WEB_IMPLEMENTATION §6.
public struct APIErrorEnvelope: Codable, Sendable, Equatable {
    public struct Body: Codable, Sendable, Equatable {
        public let code: APIErrorCode
        public let message: String
        public let requestId: String?
        public let details: [String: AnyCodable]?
    }

    public let error: Body

    enum CodingKeys: String, CodingKey { case error }
}

public struct APIError: Error, Sendable, Equatable {
    public let code: APIErrorCode
    public let message: String
    public let status: Int
    public let requestId: String?
    public let details: [String: AnyCodable]?

    public init(
        code: APIErrorCode,
        message: String,
        status: Int,
        requestId: String?,
        details: [String: AnyCodable]?,
    ) {
        self.code = code
        self.message = message
        self.status = status
        self.requestId = requestId
        self.details = details
    }

    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.code == rhs.code
            && lhs.message == rhs.message
            && lhs.status == rhs.status
            && lhs.requestId == rhs.requestId
    }
}

extension APIError {
    /// Server auth-required failures are NEVER retried by the client.
    public var isAuthFailure: Bool { code == .unauthorized }

    /// Conflict (409) means the server already accepted this idempotency key.
    /// The outbox layer uses the flag to drop the duplicate safely.
    public var isConflict: Bool { code == .conflict || status == 409 }

    /// Whether to surface the error to the user vs. retry internally.
    public var isRetryable: Bool {
        switch code {
        case .modelFailure, .toolFailure, .internal_:
            return true
        default:
            return status >= 500
        }
    }
}

/// Type-erased JSON value for error details.
public struct AnyCodable: Codable, Sendable, Equatable {
    public let value: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = ""
        } else if let s = try? container.decode(String.self) {
            self.value = s
        } else if let b = try? container.decode(Bool.self) {
            self.value = String(b)
        } else if let i = try? container.decode(Int.self) {
            self.value = String(i)
        } else if let d = try? container.decode(Double.self) {
            self.value = String(d)
        } else {
            // Last resort: re-encode nested JSON.
            let raw = try JSONSerialization.data(
                withJSONObject: try Self.toJSONObject(container: container),
                options: [],
            )
            self.value = String(data: raw, encoding: .utf8) ?? ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    private static func toJSONObject(container: SingleValueDecodingContainer) throws -> Any {
        // Best-effort: try common JSON shapes, otherwise fall back to a string.
        if let dict = try? container.decode([String: AnyCodable].self) {
            return dict.mapValues(\.value)
        }
        if let arr = try? container.decode([AnyCodable].self) {
            return arr.map(\.value)
        }
        return ""
    }
}