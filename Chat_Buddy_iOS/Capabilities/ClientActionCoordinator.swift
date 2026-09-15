import Foundation
import os

/// Coordinates native-side actions (calendar write, photo upload, share
/// sheet) and reports structured success/failure to the server.
///
/// Per skill §"Treat native capabilities as confirmed actions":
///   - show what will happen
///   - require confirmation for writes
///   - perform through the capability service
///   - return structured success/failure to server
///   - the model cannot declare a native action complete
public actor ClientActionCoordinator {
    private let http: HTTPClient
    private let calendar: CalendarCapability
    private let logger = CloudLogger.capability

    public init(http: HTTPClient, calendar: CalendarCapability) {
        self.http = http
        self.calendar = calendar
    }

    /// Propose a calendar action; the UI renders the confirmation sheet
    /// then calls `confirmCalendarAction(toolExecutionId:result:)`.
    public func proposeCalendarAction(
        operation: String,
        title: String,
        start: Date,
        end: Date,
        notes: String?,
        calendarId: String,
    ) async throws -> ProposedAction {
        struct Body: Codable {
            let operation: String
            let title: String?
            let start: String?
            let end: String?
            let notes: String?
            let eventId: String?
        }
        struct Response: Codable, Sendable {
            let toolExecutionId: String
            let requiresConfirmation: Bool
            let proposed: Body
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = Body(
            operation: operation,
            title: title,
            start: iso.string(from: start),
            end: iso.string(from: end),
            notes: notes,
            eventId: nil,
        )
        let response = try await http.send(
            Endpoints.capabilityCalendarPropose,
            method: "POST",
            body: body,
            as: Response.self,
        )
        return ProposedAction(
            toolExecutionId: response.toolExecutionId,
            requiresConfirmation: response.requiresConfirmation,
            operation: operation,
            title: title,
            start: start,
            end: end,
            notes: notes,
            calendarId: calendarId,
        )
    }

    /// User confirmed: execute the native EventKit action and post the
    /// structured result back to the server.
    public func confirmCalendarAction(
        proposed: ProposedAction,
        confirmed: Bool,
    ) async {
        do {
            if !confirmed {
                try await postResult(toolExecutionId: proposed.toolExecutionId, result: ["ok": false, "reason": "cancelled"])
                return
            }
            let created = try await calendar.createEvent(
                title: proposed.title,
                start: proposed.start,
                end: proposed.end,
                notes: proposed.notes,
                calendarId: proposed.calendarId,
            )
            try await postResult(
                toolExecutionId: proposed.toolExecutionId,
                result: [
                    "ok": true,
                    "eventId": created.id,
                    "calendarId": created.calendarId,
                ],
            )
        } catch {
            logger.error("calendar action failed: \(String(describing: error), privacy: .public)")
            try? await postResult(
                toolExecutionId: proposed.toolExecutionId,
                result: ["ok": false, "reason": String(describing: error)],
            )
        }
    }

    private func postResult(toolExecutionId: String, result: [String: Any]) async throws {
        struct Body: Codable { let toolExecutionId: String; let result: AnyJSON }
        // Encode the result as real JSON. The former AnyCodableJSON path
        // wrapped every value in a JSON *string* (double encoding) and
        // JSONSerialization rejected non-JSON values outright. AnyJSON also
        // accepts scalar Bool results JSONSerialization would refuse at
        // the top level.
        let body = Body(
            toolExecutionId: toolExecutionId,
            result: .object(result.mapValues(AnyJSON.from)),
        )
        _ = try await http.send(
            Endpoints.capabilityCalendarResult,
            method: "POST",
            body: body,
            as: EmptyResponse.self,
        )
    }
}

public struct ProposedAction: Sendable, Equatable {
    public let toolExecutionId: String
    public let requiresConfirmation: Bool
    public let operation: String
    public let title: String
    public let start: Date
    public let end: Date
    public let notes: String?
    public let calendarId: String
}
