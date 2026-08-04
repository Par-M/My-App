import Foundation
import Observation

@MainActor
@Observable
final class TaskService {
    enum SortOption: String, CaseIterable, Identifiable {
        case created = "created_at"
        case deadline = "deadline"
        case priority = "priority"
        case updated = "updated_at"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .created: "Created Date"
            case .deadline: "Deadline"
            case .priority: "Priority"
            case .updated: "Last Updated"
            }
        }
    }

    private(set) var tasks: [TaskItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var dataVersion = 0

    var showingArchived = false

    private let client: APIClient

    init(client: APIClient? = nil) {
        self.client = client ?? APIClient()
    }

    func loadTasks(
        search: String? = nil,
        priority: TaskPriority? = nil,
        status: TaskStatus? = nil,
        category: String? = nil,
        sort: SortOption? = nil,
        order: String = "asc"
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: TaskListResponse = try await client.request(
                TaskEndpoint.list(
                    search: search,
                    priority: priority,
                    status: status,
                    category: category,
                    archived: showingArchived,
                    sort: sort?.rawValue,
                    order: order
                )
            )
            tasks = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setShowingArchived(_ archived: Bool) {
        showingArchived = archived
    }

    func createTask(
        title: String,
        description: String?,
        deadline: Date?,
        priority: TaskPriority,
        status: TaskStatus,
        estimatedDuration: Int?,
        category: String?,
        notes: String?
    ) async throws -> TaskItem {
        let request = TaskCreateRequest(
            title: title,
            description: description,
            deadline: deadline,
            priority: priority,
            status: status,
            estimatedDuration: estimatedDuration,
            category: category,
            notes: notes
        )
        let created: TaskItem = try await client.request(TaskEndpoint.create(request))
        dataVersion += 1
        return created
    }

    func updateTask(_ task: TaskItem) async throws -> TaskItem {
        let updated: TaskItem = try await client.request(
            TaskEndpoint.update(id: task.id, request: TaskUpdateRequest(task: task))
        )
        dataVersion += 1
        return updated
    }

    func deleteTask(_ task: TaskItem) async throws {
        _ = try await client.request(TaskEndpoint.delete(task.id)) as MessageResponse
        dataVersion += 1
    }

    func archiveTask(_ task: TaskItem) async throws -> TaskItem {
        let updated: TaskItem = try await client.request(TaskEndpoint.archive(task.id))
        dataVersion += 1
        return updated
    }

    func restoreTask(_ task: TaskItem) async throws -> TaskItem {
        let updated: TaskItem = try await client.request(TaskEndpoint.restore(task.id))
        dataVersion += 1
        return updated
    }

    func startTask(id: UUID) async throws -> TaskItem {
        let updated: TaskItem = try await client.request(TaskEndpoint.start(id))
        replace(updated)
        dataVersion += 1
        return updated
    }

    func completeTask(id: UUID, minutes: Int?) async throws -> TaskItem {
        let updated: TaskItem = try await client.request(
            TaskEndpoint.complete(id: id, minutes: minutes)
        )
        replace(updated)
        dataVersion += 1
        return updated
    }

    func recordTime(id: UUID, minutes: Int) async throws -> TaskItem {
        let updated: TaskItem = try await client.request(
            TaskEndpoint.recordTime(id: id, minutes: minutes)
        )
        replace(updated)
        dataVersion += 1
        return updated
    }

    func snoozeTask(_ task: TaskItem, minutes: Int) async throws -> SnoozeResponse {
        let response: SnoozeResponse = try await client.request(
            TaskEndpoint.snooze(
                id: task.id,
                minutes: minutes,
                timezone: TimeZone.current.identifier
            )
        )
        replace(response.task)
        dataVersion += 1
        return response
    }

    private func replace(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }
}
