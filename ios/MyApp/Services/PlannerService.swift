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
        let existing = WidgetDataStore.read()
        let currentTitle = today?.currentTask?.title
        let nextTitle = today?.nextTasks.first?.title
        let tasksRemaining = (today?.currentTask != nil ? 1 : 0) + (today?.nextTasks.count ?? 0)

        let candidates = ([today?.currentTask].compactMap { $0 }) + (today?.nextTasks ?? [])
        let topTaskTitles = Self.topPriorityTitles(from: candidates, limit: 3)

        WidgetDataStore.write(
            currentTaskTitle: currentTitle,
            nextTaskTitle: nextTitle,
            tasksRemaining: tasksRemaining,
            habitsRemaining: existing.habitsRemaining,
            topTaskTitles: topTaskTitles
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "CurrentTaskWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "TasksRemainingWidget")
    }

    private static func topPriorityTitles(from tasks: [ScheduledTask], limit: Int) -> [String] {
        let rank: [TaskPriority: Int] = [.high: 0, .medium: 1, .low: 2]
        return Array(
            tasks
                .sorted { (rank[$0.priority] ?? 1) < (rank[$1.priority] ?? 1) }
                .prefix(limit)
                .map(\.title)
        )
    }
}
