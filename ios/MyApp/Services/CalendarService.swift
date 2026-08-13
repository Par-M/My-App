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

@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()

    private static let selectedCalendarsKey = "selectedCalendarIDs"
    private static let hasSelectionKey = "hasCustomCalendarSelection"
    private static let ignoredEventsKey = "ignoredEventIDs"

    private(set) var permission: CalendarPermission

    private(set) var selectedCalendarIDs: Set<String> = []
    private(set) var hasCustomCalendarSelection = false
    private(set) var ignoredEventIDs: Set<String> = []

    init() {
        permission = Self.currentPermission()
        selectedCalendarIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.selectedCalendarsKey) ?? []
        )
        hasCustomCalendarSelection = UserDefaults.standard.bool(
            forKey: Self.hasSelectionKey
        )
        ignoredEventIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.ignoredEventsKey) ?? []
        )
    }

    var availableCalendars: [EKCalendar] {
        store.calendars(for: .event).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
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

    func isSelected(_ calendar: EKCalendar) -> Bool {
        !hasCustomCalendarSelection
            || selectedCalendarIDs.contains(calendar.calendarIdentifier)
    }

    func setCalendarSelected(_ calendar: EKCalendar, selected: Bool) {
        if !hasCustomCalendarSelection {
            selectedCalendarIDs = Set(availableCalendars.map { $0.calendarIdentifier })
            hasCustomCalendarSelection = true
        }
        if selected {
            selectedCalendarIDs.insert(calendar.calendarIdentifier)
        } else {
            selectedCalendarIDs.remove(calendar.calendarIdentifier)
        }
        UserDefaults.standard.set(
            hasCustomCalendarSelection,
            forKey: Self.hasSelectionKey
        )
        UserDefaults.standard.set(
            Array(selectedCalendarIDs),
            forKey: Self.selectedCalendarsKey
        )
    }

    func isIgnored(_ event: CalendarEventItem) -> Bool {
        ignoredEventIDs.contains(event.id)
    }

    func toggleIgnored(_ event: CalendarEventItem) {
        if ignoredEventIDs.contains(event.id) {
            ignoredEventIDs.remove(event.id)
        } else {
            ignoredEventIDs.insert(event.id)
        }
        UserDefaults.standard.set(Array(ignoredEventIDs), forKey: Self.ignoredEventsKey)
    }

    func fetchEvents(from start: Date, to end: Date) -> [CalendarEventItem] {
        let calendars: [EKCalendar]?
        if hasCustomCalendarSelection {
            let ids = selectedCalendarIDs
            calendars = availableCalendars.filter { ids.contains($0.calendarIdentifier) }
        } else {
            calendars = nil
        }
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
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
}
