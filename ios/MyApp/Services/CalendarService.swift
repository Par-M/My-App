import EventKit
import Foundation
import Observation

enum CalendarPermission: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

struct CalendarEventItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

enum CalendarServiceError: LocalizedError {
    case noDefaultCalendar
    case eventNotFound

    var errorDescription: String? {
        switch self {
        case .noDefaultCalendar:
            return "No calendar is available for creating events."
        case .eventNotFound:
            return "The calendar event could not be found."
        }
    }
}

@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()

    private(set) var permission: CalendarPermission

    init() {
        permission = Self.currentPermission()
    }

    static func currentPermission() -> CalendarPermission {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    @discardableResult
    func requestPermission() async -> CalendarPermission {
        do {
            let granted = try await store.requestFullAccessToEvents()
            permission = granted ? .granted : .denied
        } catch {
            permission = .denied
        }
        return permission
    }

    func fetchEvents(from start: Date, to end: Date) -> [CalendarEventItem] {
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )
        return store.events(matching: predicate).map { event in
            CalendarEventItem(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay
            )
        }
    }

    @discardableResult
    func createTaskBlock(title: String, start: Date, end: Date) throws -> String {
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarServiceError.noDefaultCalendar
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    func updateTaskBlock(
        eventIdentifier: String,
        title: String? = nil,
        start: Date? = nil,
        end: Date? = nil
    ) throws {
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            throw CalendarServiceError.eventNotFound
        }
        if let title {
            event.title = title
        }
        if let start {
            event.startDate = start
        }
        if let end {
            event.endDate = end
        }
        try store.save(event, span: .thisEvent)
    }

    func deleteTaskBlock(eventIdentifier: String) throws {
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            return
        }
        try store.remove(event, span: .thisEvent)
    }
}
