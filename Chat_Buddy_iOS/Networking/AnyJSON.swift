import Foundation

/// Type-erased JSON value that encodes as *real* JSON.
///
/// `AnyCodableJSON` (RealtimeClient.swift) stores its payload as a raw
/// string and its `encode(to:)` writes that string as a JSON *string* —
/// correct for opaque realtime payloads, but it double-encodes anything
/// put into a structured request body. Use `AnyJSON` when the server
/// must receive an actual JSON object/array/scalar.
public enum AnyJSON: Codable, Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    /// Lossy conversion from arbitrary values (JSONSerialization-compatible
    /// shapes plus scalars). Unrecognized values degrade to their string
    /// description instead of throwing.
    public static func from(_ value: Any) -> AnyJSON {
        switch value {
        case let v as Bool:
            return .bool(v) // Bool before Int: Bool bridges to NSNumber
        case let v as Int:
            return .number(Double(v))
        case let v as Double:
            return .number(v)
        case let v as String:
            return .string(v)
        case let v as [Any]:
            return .array(v.map(from))
        case let v as [String: Any]:
            return .object(v.mapValues(from))
        default:
            return .string(String(describing: value))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyJSON].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: AnyJSON].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unsupported JSON value",
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let v):
            try container.encode(v)
        case .number(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        case .object(let v):
            try container.encode(v)
        }
    }
}
