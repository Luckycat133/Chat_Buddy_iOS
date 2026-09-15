import Foundation
import os

/// Authenticated WebSocket client for the cloud realtime channel.
///
/// Per DOMAIN_ARCHITECTURE §12 + skill §"Realtime client":
///   - heartbeat
///   - reconnect with bounded backoff
///   - resume from last event ID
///   - detect event gap → trigger delta sync
///   - deduplicate by event id
///   - expose connection state
///   - pause/reconnect on app lifecycle changes
///   - No event may be applied twice.
public actor RealtimeClient {
    public enum State: String, Sendable, Equatable {
        case idle
        case connecting
        case connected
        case backoff
        case failed
    }

    public struct RealtimeEvent: Sendable, Equatable, Codable {
        public let channel: String
        public let id: String
        public let createdAt: Date
        public let payload: AnyCodableJSON
    }

    private let environment: AppEnvironment
    private let session: AuthSession
    private var eventHandler: @Sendable (RealtimeEvent) async -> Void
    private var syncTrigger: @Sendable () async -> Void
    private let logger = CloudLogger.realtime

    private var task: URLSessionWebSocketTask?
    private var lastEventId: String?
    private var backoff: TimeInterval = 0.5
    private let maxBackoff: TimeInterval = 30
    private var stateValue: State = .idle
    private var explicitPause: Bool = false
    private var continuation: Task<Void, Never>?

    public init(
        environment: AppEnvironment,
        session: AuthSession,
        onEvent: @escaping @Sendable (RealtimeEvent) async -> Void,
        onGap: @escaping @Sendable () async -> Void,
    ) {
        self.environment = environment
        self.session = session
        self.eventHandler = onEvent
        self.syncTrigger = onGap
    }

    /// Replace the event/gap handlers after init. Needed because the
    /// owning app state cannot capture `self` inside its own initializer.
    public func setHandlers(
        onEvent: @escaping @Sendable (RealtimeEvent) async -> Void,
        onGap: @escaping @Sendable () async -> Void,
    ) {
        self.eventHandler = onEvent
        self.syncTrigger = onGap
    }

    public func currentState() async -> State { stateValue }

    /// Open the WebSocket. Caller invokes again on app foreground.
    public func connect() async {
        guard !explicitPause else { return }
        guard let token = await session.currentAccessToken() else {
            logger.notice("realtime connect skipped: no token")
            stateValue = .idle
            return
        }
        guard task == nil else { return }
        stateValue = .connecting

        var request = URLRequest(url: environment.realtimeURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(environment.bundleIdentifier, forHTTPHeaderField: "x-client")
        if let last = lastEventId {
            request.setValue(last, forHTTPHeaderField: "last-event-id")
        }
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        task = socket
        stateValue = .connected
        backoff = 0.5
        continuation = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    /// Pause without disconnecting (e.g., app background).
    public func pause() async {
        explicitPause = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation?.cancel()
        continuation = nil
        stateValue = .idle
    }

    /// Resume after pause (app foreground).
    public func resume() async {
        explicitPause = false
        await connect()
    }

    /// Hard disconnect and clear state.
    public func disconnect() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation?.cancel()
        continuation = nil
        stateValue = .idle
    }

    /// Mark the last successfully applied event id for resume.
    public func markApplied(eventId: String) {
        lastEventId = eventId
    }

    private func receiveLoop() async {
        guard let task = task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    await handle(data: data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        await handle(data: data)
                    }
                @unknown default:
                    logger.notice("unknown websocket message case")
                }
            } catch {
                logger.notice("realtime receive error: \(String(describing: error), privacy: .public)")
                stateValue = .backoff
                self.task = nil
                let delay = min(backoff * 2, maxBackoff)
                backoff = max(delay, 0.5)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !explicitPause {
                    await connect()
                }
                return
            }
        }
    }

    private func handle(data: Data) async {
        guard let envelope = try? JSONDecoder.iso8601WithFractional.decode(RealtimeEnvelope.self, from: data) else {
            logger.error("realtime decode failed")
            await syncTrigger()
            return
        }
        switch envelope {
        case .event(let event):
            if event.id == lastEventId { return } // dedupe
            lastEventId = event.id
            await eventHandler(event)
        case .gap:
            await syncTrigger()
        case .ping:
            task?.sendPing { _ in }
        }
    }
}

private enum RealtimeEnvelope: Decodable {
    case event(RealtimeClient.RealtimeEvent)
    case gap
    case ping

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "gap":
            self = .gap
        case "ping":
            self = .ping
        default:
            let event = try RealtimeClient.RealtimeEvent(
                channel: container.decode(String.self, forKey: .channel),
                id: container.decode(String.self, forKey: .id),
                createdAt: container.decode(Date.self, forKey: .createdAt),
                payload: container.decode(AnyCodableJSON.self, forKey: .payload),
            )
            self = .event(event)
        }
    }

    private enum CodingKeys: String, CodingKey { case type, channel, id, createdAt, payload }
}

/// JSON value wrapper used by realtime payloads. The server publishes
/// opaque JSON; the iOS client does not attempt to decode the contents
/// unless a dedicated repository handles that channel.
public struct AnyCodableJSON: Codable, Sendable, Equatable {
    public let raw: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.raw = "{}"
            return
        }
        let rawData = try JSONSerialization.data(
            withJSONObject: try decodeValue(container: container),
            options: [.sortedKeys],
        )
        self.raw = String(data: rawData, encoding: .utf8) ?? "{}"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    private func decodeValue(container: SingleValueDecodingContainer) throws -> Any {
        if let v = try? container.decode(Bool.self) { return v }
        if let v = try? container.decode(Int.self) { return v }
        if let v = try? container.decode(Double.self) { return v }
        if let v = try? container.decode(String.self) { return v }
        if let v = try? container.decode([AnyCodableJSON].self) {
            return v.map(\.raw)
        }
        if let v = try? container.decode([String: AnyCodableJSON].self) {
            return v.mapValues(\.raw)
        }
        return NSNull()
    }
}

extension JSONDecoder {
    nonisolated fileprivate static var iso8601WithFractional: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601WithFractional
        return d
    }
}