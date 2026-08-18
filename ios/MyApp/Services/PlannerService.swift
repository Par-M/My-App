import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class PlannerService {
    private(set) var today: TodayResponse?
    private(set) var summary: DailySummaryResponse?
    private(set) var missedReasons: MissedReasonsResponse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client: APIClient

    init(client: APIClient? = nil) {
        self.client = client ?? APIClient()
    }

    func loadToday() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            today = try await client.request(
                PlannerEndpoint.today(timezone: TimeZone.current.identifier)
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        updateWidget()
    }

    func loadSummary() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            summary = try await client.request(
                PlannerEndpoint.dailySummary(timezone: TimeZone.current.identifier)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMissedReasons() async {
        errorMessage = nil
        do {
            missedReasons = try await client.request(PlannerEndpoint.missedReasons)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentError(_ message: String) {
        errorMessage = message
    }

    func updateWidget() {
        let cal = Calendar.current
        let now = Date()
        var workEndComponents = cal.dateComponents([.year, .month, .day], from: now)
        workEndComponents.hour = 17
        workEndComponents.minute = 0
        let workEnd = cal.date(from: workEndComponents) ?? now

        let existing = WidgetDataStore.read()

        WidgetDataStore.write(
            taskTitle: today?.currentTask?.title,
            taskEnd: today?.currentTask?.end,
            workEndDate: workEnd,
            habitsDone: existing.habitsDone,
            habitsTotal: existing.habitsTotal
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "CurrentTaskWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "TasksRemainingWidget")
    }
}
