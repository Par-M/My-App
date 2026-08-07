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
    private(set) var isOfflineMode = false

    var showingArchived = false

    private let client: APIClient
    private let store: LocalStore?
    private let connectivity: ConnectivityMonitor

    init(
        client: APIClient? = nil,
        store: LocalStore? = nil,
        connectivity: ConnectivityMonitor? = nil
    ) {
        self.client = client ?? APIClient()
        self.store = store
        self.connectivity = connectivity ?? ConnectivityMonitor()
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
            store?.upsertServerTasks(response.items)
            isOfflineMode = false
        } catch {
            if let store, isNetworkUnavailable(error) || !connectivity.isConnected {
                tasks = store.tasks()
                isOfflineMode = true
                errorMessage = "Offline — showing saved tasks. Changes will sync when you're back online."
            } else {
                errorMessage = error.localizedDescription
            }
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

        if !connectivity.isConnected, let store {
            let now = Date()
            let local = TaskItem(
                id: UUID(),
                userId: UUID(),
                title: request.title,
                description: request.description,
                deadline: request.deadline,
                priority: request.priority,
                status: request.status,
                estimatedDuration: request.estimatedDuration,
                actualDuration: nil,
                productivity: nil,
                startedAt: nil,
                completedAt: nil,
                category: request.category,
                notes: request.notes,
                isArchived: false,
                createdAt: now,
                updatedAt: now
            )
            store.upsert(local, dirty: true)
            tasks.insert(local, at: 0)
            isOfflineMode = true
            dataVersion += 1
            return local
        }

        do {
            let created: TaskItem = try await client.request(TaskEndpoint.create(request))
            store?.upsert(created)
            tasks.insert(created, at: 0)
            isOfflineMode = false
            dataVersion += 1
            return created
        } catch {
            if let store, isNetworkUnavailable(error) {
                let now = Date()
                let local = TaskItem(
                    id: UUID(),
                    userId: UUID(),
                    title: request.title,
                    description: request.description,
                    deadline: request.deadline,
                    priority: request.priority,
                    status: request.status,
                    estimatedDuration: request.estimatedDuration,
                    actualDuration: nil,
                    productivity: nil,
                    startedAt: nil,
                    completedAt: nil,
                    category: request.category,
                    notes: request.notes,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now
                )
                store.upsert(local, dirty: true)
                tasks.insert(local, at: 0)
                isOfflineMode = true
                dataVersion += 1
                return local
            }
            throw error
        }
    }

    func updateTask(_ task: TaskItem) async throws -> TaskItem {
        if !connectivity.isConnected, let store {
            let local = bump(task)
            store.upsert(local, dirty: true)
            replace(local)
            isOfflineMode = true
            dataVersion += 1
            return local
        }

        do {
            let updated: TaskItem = try await client.request(
                TaskEndpoint.update(id: task.id, request: TaskUpdateRequest(task: task))
            )
            store?.upsert(updated)
            replace(updated)
            isOfflineMode = false
            dataVersion += 1
            return updated
        } catch {
            if let store, isNetworkUnavailable(error) {
                let local = bump(task)
                store.upsert(local, dirty: true)
                replace(local)
                isOfflineMode = true
                dataVersion += 1
                return local
            }
            throw error
        }
    }

    func deleteTask(_ task: TaskItem) async throws {
        if !connectivity.isConnected, let store {
            store.markDeleted(taskId: task.id)
            isOfflineMode = true
        } else {
            do {
                _ = try await client.request(TaskEndpoint.delete(task.id)) as MessageResponse
                store?.purgeTask(id: task.id)
                isOfflineMode = false
            } catch {
                if let store, isNetworkUnavailable(error) {
                    store.markDeleted(taskId: task.id)
                    isOfflineMode = true
                } else {
                    throw error
                }
            }
        }
        tasks.removeAll { $0.id == task.id }
        dataVersion += 1
    }

    func archiveTask(_ task: TaskItem) async throws -> TaskItem {
        try await toggleArchived(task, archived: true)
    }

    func restoreTask(_ task: TaskItem) async throws -> TaskItem {
        try await toggleArchived(task, archived: false)
    }

    private func toggleArchived(_ task: TaskItem, archived: Bool) async throws -> TaskItem {
        var updated = task
        updated.isArchived = archived

        if !connectivity.isConnected, let store {
            let local = bump(updated)
            store.upsert(local, dirty: true)
            replace(local)
            isOfflineMode = true
            dataVersion += 1
            return local
        }

        do {
            let server: TaskItem = try await client.request(
                archived ? TaskEndpoint.archive(task.id) : TaskEndpoint.restore(task.id)
            )
            store?.upsert(server)
            replace(server)
            isOfflineMode = false
            dataVersion += 1
            return server
        } catch {
            if let store, isNetworkUnavailable(error) {
                let local = bump(updated)
                store.upsert(local, dirty: true)
                replace(local)
                isOfflineMode = true
                dataVersion += 1
                return local
            }
            throw error
        }
    }

    func startTask(id: UUID) async throws -> TaskItem {
        if !connectivity.isConnected, let store, let current = tasks.first(where: { $0.id == id }) {
            var updated = current
            updated.status = .inProgress
            updated.startedAt = Date()
            let local = bump(updated)
            store.upsert(local, dirty: true)
            replace(local)
            isOfflineMode = true
            dataVersion += 1
            return local
        }

        do {
            let updated: TaskItem = try await client.request(TaskEndpoint.start(id))
            store?.upsert(updated)
            replace(updated)
            isOfflineMode = false
            dataVersion += 1
            return updated
        } catch {
            if let store, isNetworkUnavailable(error), let current = tasks.first(where: { $0.id == id }) {
                var updated = current
                updated.status = .inProgress
                updated.startedAt = Date()
                let local = bump(updated)
                store.upsert(local, dirty: true)
                replace(local)
                isOfflineMode = true
                dataVersion += 1
                return local
            }
            throw error
        }
    }

    func completeTask(
        id: UUID,
        minutes: Int?,
        productivity: TaskProductivity? = nil
    ) async throws -> TaskItem {
        if !connectivity.isConnected, let store, let current = tasks.first(where: { $0.id == id }) {
            var updated = current
            updated.status = .completed
            updated.completedAt = Date()
            updated.productivity = productivity
            if let minutes {
                updated.actualDuration = minutes
            }
            let local = bump(updated)
            store.upsert(local, dirty: true)
            replace(local)
            isOfflineMode = true
            dataVersion += 1
            return local
        }

        do {
            let updated: TaskItem = try await client.request(
                TaskEndpoint.complete(id: id, minutes: minutes, productivity: productivity)
            )
            store?.upsert(updated)
            replace(updated)
            isOfflineMode = false
            dataVersion += 1
            return updated
        } catch {
            if let store, isNetworkUnavailable(error), let current = tasks.first(where: { $0.id == id }) {
                var updated = current
                updated.status = .completed
                updated.completedAt = Date()
                updated.productivity = productivity
                if let minutes {
                    updated.actualDuration = minutes
                }
                let local = bump(updated)
                store.upsert(local, dirty: true)
                replace(local)
                isOfflineMode = true
                dataVersion += 1
                return local
            }
            throw error
        }
    }

    func recordTime(id: UUID, minutes: Int) async throws -> TaskItem {
        if !connectivity.isConnected, let store, let current = tasks.first(where: { $0.id == id }) {
            var updated = current
            updated.actualDuration = (updated.actualDuration ?? 0) + minutes
            let local = bump(updated)
            store.upsert(local, dirty: true)
            replace(local)
            isOfflineMode = true
            dataVersion += 1
            return local
        }

        do {
            let updated: TaskItem = try await client.request(
                TaskEndpoint.recordTime(id: id, minutes: minutes)
            )
            store?.upsert(updated)
            replace(updated)
            isOfflineMode = false
            dataVersion += 1
            return updated
        } catch {
            if let store, isNetworkUnavailable(error), let current = tasks.first(where: { $0.id == id }) {
                var updated = current
                updated.actualDuration = (updated.actualDuration ?? 0) + minutes
                let local = bump(updated)
                store.upsert(local, dirty: true)
                replace(local)
                isOfflineMode = true
                dataVersion += 1
                return local
            }
            throw error
        }
    }

    func snoozeTask(_ task: TaskItem, minutes: Int) async throws -> SnoozeResponse {
        if !connectivity.isConnected, let store {
            var updated = task
            if let deadline = task.deadline {
                updated.deadline = deadline.addingTimeInterval(TimeInterval(minutes * 60))
            }
            let local = bump(updated)
            store.upsert(local, dirty: true)
            replace(local)
            isOfflineMode = true
            dataVersion += 1
            return SnoozeResponse(task: local, blocks: [])
        }

        do {
            let response: SnoozeResponse = try await client.request(
                TaskEndpoint.snooze(
                    id: task.id,
                    minutes: minutes,
                    timezone: TimeZone.current.identifier
                )
            )
            store?.upsert(response.task)
            replace(response.task)
            store?.upsertServerBlocks(response.blocks)
            isOfflineMode = false
            dataVersion += 1
            return response
        } catch {
            if let store, isNetworkUnavailable(error) {
                var updated = task
                if let deadline = task.deadline {
                    updated.deadline = deadline.addingTimeInterval(TimeInterval(minutes * 60))
                }
                let local = bump(updated)
                store.upsert(local, dirty: true)
                replace(local)
                isOfflineMode = true
                dataVersion += 1
                return SnoozeResponse(task: local, blocks: [])
            }
            throw error
        }
    }

    private func bump(_ task: TaskItem) -> TaskItem {
        var updated = task
        updated.updatedAt = Date()
        return updated
    }

    private func replace(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            tasks.insert(task, at: 0)
            return
        }
        tasks[index] = task
    }
}
