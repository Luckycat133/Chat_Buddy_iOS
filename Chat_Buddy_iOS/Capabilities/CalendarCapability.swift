import Foundation
import EventKit
import os

/// Calendar capability per skill §"Calendar with EventKit":
///   - request permission only after user/character invokes calendar
///   - read selected calendars per settings
///   - do NOT upload full calendar content without clear consent
///   - any create/update/delete shows a confirmation sheet
///   - success is claimed only after EventKit returns a result
///   - server receives the structured success/failure
public actor CalendarCapability {
    private let store = EKEventStore()
    private let logger = CloudLogger.capability

    public enum PermissionOutcome: Sendable, Equatable {
        case granted
        case denied
        case restricted
    }

    public enum ActionError: Error, Sendable {
        case cancelled
        case denied
        case failure(String)
    }

    public init() {}

    public func requestAccess() async -> PermissionOutcome {
        if #available(iOS 17.0, *) {
            do {
                let granted = try await store.requestFullAccessToEvents()
                return granted ? .granted : .denied
            } catch {
                return .denied
            }
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        }
    }

    /// Read events from selected calendars within a date range. Caller
    /// passes the allowed calendar IDs from settings — the capability
    /// does not enumerate all calendars without explicit consent.
    public func readEvents(
        calendarIds: [String],
        from: Date,
        to: Date,
    ) async throws -> [EventDigest] {
        guard !calendarIds.isEmpty else {
            throw ActionError.failure("no calendars selected")
        }
        let calendars = store.calendars(for: .event).filter {
            guard let id = $0.calendarIdentifier as String? else { return false }
            return calendarIds.contains(id)
        }
        let predicate = store.predicateForEvents(
            withStart: from,
            end: to,
            calendars: calendars,
        )
        let events = store.events(matching: predicate)
        return events.map { event in
            EventDigest(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                calendarId: event.calendar.calendarIdentifier,
                notes: event.notes,
            )
        }
    }

    /// Create an event after explicit user confirmation. Returns the
    /// created event id and the success/failure for the server.
    public func createEvent(
        title: String,
        start: Date,
        end: Date,
        notes: String?,
        calendarId: String,
    ) async throws -> CreatedEvent {
        let outcome = await requestAccess()
        guard outcome == .granted else {
            throw ActionError.denied
        }
        guard let calendar = store.calendar(withIdentifier: calendarId) else {
            throw ActionError.failure("calendar not found")
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent)
            return CreatedEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                calendarId: calendarId,
            )
        } catch {
            throw ActionError.failure(String(describing: error))
        }
    }
}

public struct EventDigest: Sendable, Equatable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarId: String
    public let notes: String?
}

public struct CreatedEvent: Sendable, Equatable {
    public let id: String
    public let calendarId: String
}

/// Confirmation sheet content for any write action. UI binds to this and
/// posts the result to `/v1/capabilities/calendar/result`.
public struct CalendarActionConfirmation: Sendable, Equatable {
    public let toolExecutionId: String
    public let action: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarName: String
    public let notes: String?
}