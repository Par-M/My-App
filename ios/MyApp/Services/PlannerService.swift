import Foundation
import Observation

@MainActor
@Observable
final class PlannerService {
    private(set) var today: TodayResponse?
    private(set) var summary: DailySummaryResponse?
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

    func presentError(_ message: String) {
        errorMessage = message
    }
}
