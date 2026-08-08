import Foundation
import Observation

@MainActor
@Observable
final class HabitService {
    private(set) var dashboard: HabitDashboard?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var dataVersion = 0

    private let client: APIClient

    init(client: APIClient? = nil) {
        self.client = client ?? APIClient()
    }

    var habits: [HabitStats] {
        dashboard?.habits ?? []
    }

    func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dashboard = try await client.request(HabitEndpoint.dashboard)
            errorMessage = nil
            dataVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createHabit(
        title: String,
        repeatWeekdays: [Int]?,
        dailyGoal: Int
    ) async -> Habit? {
        let request = HabitCreateRequest(
            title: title,
            repeatWeekdays: repeatWeekdays,
            dailyGoal: dailyGoal
        )
        do {
            let habit: Habit = try await client.request(HabitEndpoint.create(request))
            await loadDashboard()
            return habit
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func updateHabit(
        id: UUID,
        title: String,
        repeatWeekdays: [Int]?,
        dailyGoal: Int
    ) async -> Habit? {
        let request = HabitUpdateRequest(
            title: title,
            repeatWeekdays: repeatWeekdays,
            dailyGoal: dailyGoal
        )
        do {
            let habit: Habit = try await client.request(
                HabitEndpoint.update(id: id, request: request)
            )
            await loadDashboard()
            return habit
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteHabit(id: UUID) async {
        do {
            let _: MessageResponse = try await client.request(HabitEndpoint.delete(id))
            await loadDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logHabit(id: UUID, count: Int, date: Date? = nil) async {
        do {
            let _: HabitLog = try await client.request(
                HabitEndpoint.log(id: id, count: count, date: date)
            )
            await loadDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setHabitDayCount(id: UUID, count: Int, date: Date? = nil) async {
        do {
            let _: HabitDaySetResponse = try await client.request(
                HabitEndpoint.setDay(id: id, count: count, date: date)
            )
            await loadDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
