import Foundation
import Observation

@MainActor
@Observable
final class FocusService {
    private(set) var dailySessions: [FocusSession] = []
    private(set) var reflections: [Reflection] = []
    private(set) var summary: FocusSummary?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var dataVersion = 0

    private let client: APIClient

    init(client: APIClient? = nil) {
        self.client = client ?? APIClient()
    }

    func loadFocus(after: Date? = nil, before: Date? = nil) async {
        isLoading = true
        defer { isLoading = false }
        async let sessions = loadSessions(after: after, before: before)
        async let summary = loadSummary(after: after, before: before)
        async let reflections = loadReflections()
        _ = await (sessions, summary, reflections)
    }

    @discardableResult
    func createSession(
        taskID: UUID?,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int? = nil
    ) async -> FocusSession? {
        let payload = FocusSessionCreate(
            taskID: taskID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds
        )
        do {
            let session: FocusSession = try await client.request(FocusEndpoint.create(payload))
            dataVersion += 1
            await loadFocus()
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteSession(id: UUID) async {
        do {
            _ = try await client.request(FocusEndpoint.deleteSession(id)) as MessageResponse
            dataVersion += 1
            await loadFocus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createReflection(date: Date, text: String) async -> Reflection? {
        let payload = ReflectionCreate(date: date, text: text)
        do {
            let reflection: Reflection = try await client.request(FocusEndpoint.createReflection(payload))
            dataVersion += 1
            await loadReflections()
            return reflection
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func requestAnalysis(reflectionID: UUID) async -> String? {
        do {
            let response: ReflectionAnalysisResponse = try await client.request(
                FocusEndpoint.analysis(reflectionID)
            )
            dataVersion += 1
            return response.analysis
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteReflection(id: UUID) async {
        do {
            _ = try await client.request(FocusEndpoint.deleteReflection(id)) as MessageResponse
            dataVersion += 1
            await loadReflections()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSessions(after: Date? = nil, before: Date? = nil) async {
        do {
            let response: [FocusSession] = try await client.request(FocusEndpoint.sessions)
            dailySessions = response
            dataVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSummary(after: Date? = nil, before: Date? = nil) async {
        do {
            let response: FocusSummary = try await client.request(
                FocusEndpoint.summary(after: after, before: before)
            )
            summary = response
            dataVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadReflections() async {
        do {
            let response: [Reflection] = try await client.request(FocusEndpoint.reflections)
            reflections = response
            dataVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
