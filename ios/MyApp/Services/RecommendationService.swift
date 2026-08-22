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

    func load(from start: Date, to end: Date, excluding eventIDs: Set<String> = []) async {
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == requestGeneration { isLoading = false } }

        var busyTimes: [BusyTimeRequest] = []
        if let calendarService, calendarService.permission == .granted {
            busyTimes = calendarService
                .fetchEvents(from: start, to: end)
                .filter {
                    !eventIDs.contains($0.id) && !$0.isAllDay && !calendarService.isIgnored($0)
                }
                .map { BusyTimeRequest(start: $0.start, end: $0.end) }
        }

        let request = DailyRecommendationsRequest(
            timezone: TimeZone.current.identifier,
            startDate: Calendar.current.startOfDay(for: start),
            endDate: end,
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

    func clear() {
        days = []
        unscheduled = []
    }

    func recommendations(for day: Date) -> DayRecommendation? {
        let calendar = Calendar.current
        return days.first { calendar.isDate($0.date, inSameDayAs: day) }
    }
}
