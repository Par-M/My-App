import Foundation
import Observation

@MainActor
@Observable
final class RecommendationService {
    private(set) var days: [DayRecommendation] = []
    private(set) var unscheduled: [UnscheduledPart] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client: APIClient
    private let calendarService: CalendarService?
    private var requestGeneration = 0

    init(client: APIClient? = nil, calendarService: CalendarService? = nil) {
        self.client = client ?? APIClient()
        self.calendarService = calendarService
    }

    func load(
        from start: Date,
        to end: Date,
        excluding eventIDs: Set<String> = [],
        force: Bool = false
    ) async {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let requestStart = min(calendar.startOfDay(for: start), todayStart)
        let existing = coverageRange()

        // Keep one stable, growing plan window: anchoring the start at the
        // earliest of (requested start, any already-planned start, today) and
        // only ever extending the end. Toggling between upcoming days then
        // shows each day's slice of the same spread-out plan instead of
        // recomputing a fresh single-day plan (which repeated the same urgent
        // tasks and marked everything else "doesn't fit this window").
        let planStart = {
            var start = requestStart
            if let existing { start = min(start, existing.start) }
            return start
        }()
        let planEnd = max(end, existing?.end ?? end)

        // If the requested range is already covered and nothing changed, keep
        // the cached plan so toggling days is instant and stable.
        if !force,
           let existing,
           existing.start <= requestStart,
           existing.end >= end {
            return
        }

        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == requestGeneration { isLoading = false } }

        var busyTimes: [BusyTimeRequest] = []
        if let calendarService, calendarService.permission == .granted {
            busyTimes = calendarService
                .fetchEvents(from: planStart, to: planEnd)
                .filter {
                    !eventIDs.contains($0.id) && !$0.isAllDay && !calendarService.isIgnored($0)
                }
                .map { BusyTimeRequest(start: $0.start, end: $0.end) }
        }

        let request = DailyRecommendationsRequest(
            timezone: TimeZone.current.identifier,
            startDate: planStart,
            endDate: planEnd,
            busyTimes: busyTimes
        )

        do {
            let response: DailyRecommendationsResponse = try await client.request(
                RecommendationEndpoint.daily(request)
            )
            guard generation == requestGeneration else { return }
            days = response.days
            unscheduled = response.unscheduled
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func coverageRange() -> (start: Date, end: Date)? {
        guard let first = days.first?.date, let last = days.last?.date else {
            return nil
        }
        return (min(first, last), max(first, last))
    }

    func recommendations(for day: Date) -> DayRecommendation? {
        let calendar = Calendar.current
        return days.first { calendar.isDate($0.date, inSameDayAs: day) }
    }
}
