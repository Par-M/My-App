import Foundation
import Observation

@MainActor
@Observable
final class SyncManager {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastSyncError: String?
    var pendingCount: Int { store.pendingChangeCount() }

    private let store: LocalStore
    private let connectivity: ConnectivityMonitor
    private let client: APIClient

    init(
        store: LocalStore,
        connectivity: ConnectivityMonitor,
        client: APIClient? = nil
    ) {
        self.store = store
        self.connectivity = connectivity
        self.client = client ?? APIClient()
        self.lastSyncDate = store.lastSyncDate()
    }

    func syncNow() async {
        guard !isSyncing else { return }
        guard connectivity.isConnected else {
            lastSyncError = "Offline — changes will sync when you're back online."
            return
        }
        guard KeychainManager().accessToken != nil else { return }

        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            try await uploadTasks()
            try await uploadBlocks()
            try await downloadChanges()
            let now = Date()
            store.setLastSyncDate(now)
            lastSyncDate = now
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Upload

    private func uploadTasks() async throws {
        for local in store.dirtyTasks() {
            if local.isDeleted {
                if local.syncedAt != nil {
                    _ = try? await client.request(TaskEndpoint.delete(local.id)) as MessageResponse
                }
                store.purgeTask(id: local.id)
                continue
            }

            if local.syncedAt == nil {
                let created: TaskItem = try await client.request(
                    TaskEndpoint.create(TaskCreateRequest(from: local))
                )
                store.replaceTask(id: local.id, with: created, syncedAt: Date())
            } else {
                do {
                    let updated: TaskItem = try await client.request(
                        TaskEndpoint.update(id: local.id, request: TaskUpdateRequest(from: local))
                    )
                    store.replaceTask(id: local.id, with: updated, syncedAt: Date())
                } catch NetworkError.httpStatus(404) {
                    let created: TaskItem = try await client.request(
                        TaskEndpoint.create(TaskCreateRequest(from: local))
                    )
                    store.replaceTask(id: local.id, with: created, syncedAt: Date())
                }
            }
        }
    }

    private func uploadBlocks() async throws {
        for local in store.dirtyBlocks() {
            if local.isDeleted {
                if local.syncedAt != nil {
                    _ = try? await client.request(CalendarEndpoint.deleteBlock(local.id)) as MessageResponse
                }
                store.purgeBlock(id: local.id)
                continue
            }

            if local.syncedAt == nil {
                let created: CalendarBlock = try await client.request(
                    CalendarEndpoint.createBlock(CalendarBlockCreateRequest(from: local))
                )
                store.replaceBlock(id: local.id, with: created, syncedAt: Date())
            } else {
                do {
                    let updated: CalendarBlock = try await client.request(
                        CalendarEndpoint.updateBlock(
                            id: local.id,
                            request: CalendarBlockUpdateRequest(from: local)
                        )
                    )
                    store.replaceBlock(id: local.id, with: updated, syncedAt: Date())
                } catch NetworkError.httpStatus(404) {
                    let created: CalendarBlock = try await client.request(
                        CalendarEndpoint.createBlock(CalendarBlockCreateRequest(from: local))
                    )
                    store.replaceBlock(id: local.id, with: created, syncedAt: Date())
                }
            }
        }
    }

    // MARK: - Download

    private func downloadChanges() async throws {
        let since = store.lastSyncDate()

        let taskResponse: TaskListResponse = try await client.request(
            TaskEndpoint.list(
                search: nil,
                priority: nil,
                status: nil,
                category: nil,
                archived: true,
                sort: nil,
                order: "asc",
                since: since
            )
        )
        store.upsertServerTasks(taskResponse.items)

        let blockResponse: CalendarBlockListResponse = try await client.request(
            CalendarEndpoint.listBlocks(since: since)
        )
        store.upsertServerBlocks(blockResponse.items)

        if since == nil, pendingCount == 0 {
            mirrorServer(taskIds: taskResponse.items.map(\.id), blockIds: blockResponse.items.map(\.id))
        }
    }

    private func mirrorServer(taskIds: [UUID], blockIds: [UUID]) {
        let taskSet = Set(taskIds)
        for task in store.tasks() where !taskSet.contains(task.id) {
            store.purgeTask(id: task.id)
        }
        let blockSet = Set(blockIds)
        for block in store.blocks() where !blockSet.contains(block.id) {
            store.purgeBlock(id: block.id)
        }
    }
}
