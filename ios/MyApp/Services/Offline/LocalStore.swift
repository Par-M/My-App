import Foundation
import SwiftData

@MainActor
final class LocalStore {
    static let shared = LocalStore()

    let container: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) {
        let schema = Schema([LocalTask.self, LocalBlock.self, SyncMetadata.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            self.container = container
        } else if let fallback = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ) {
            self.container = fallback
        } else {
            fatalError("Failed to create SwiftData container")
        }
        context = ModelContext(container)
    }

    // MARK: - Tasks

    func tasks() -> [TaskItem] {
        let predicate = #Predicate<LocalTask> { !$0.isDeleted }
        let all = (try? context.fetch(FetchDescriptor<LocalTask>(predicate: predicate))) ?? []
        return all
            .map(\.taskItem)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func task(id: UUID) -> TaskItem? {
        let predicate = #Predicate<LocalTask> { $0.id == id && !$0.isDeleted }
        let all = (try? context.fetch(FetchDescriptor<LocalTask>(predicate: predicate))) ?? []
        return all.first?.taskItem
    }

    func upsert(_ task: TaskItem, dirty: Bool = false, deleted: Bool = false, syncedAt: Date? = nil) {
        if let existing = fetchTask(id: task.id) {
            existing.id = task.id
            existing.userId = task.userId
            existing.title = task.title
            existing.taskDescription = task.description
            existing.deadline = task.deadline
            existing.priorityRaw = task.priority.rawValue
            existing.statusRaw = task.status.rawValue
            existing.estimatedDuration = task.estimatedDuration
            existing.actualDuration = task.actualDuration
            existing.startedAt = task.startedAt
            existing.completedAt = task.completedAt
            existing.category = task.category
            existing.notes = task.notes
            existing.isArchived = task.isArchived
            existing.createdAt = task.createdAt
            existing.updatedAt = task.updatedAt
            existing.isDirty = dirty
            existing.isDeleted = deleted
            existing.syncedAt = syncedAt
        } else {
            context.insert(
                LocalTask(task: task, isDirty: dirty, isDeleted: deleted, syncedAt: syncedAt)
            )
        }
        save()
    }

    func upsertServerTasks(_ serverTasks: [TaskItem]) {
        for server in serverTasks {
            if let existing = fetchTask(id: server.id), existing.isDirty || existing.isDeleted {
                continue
            }
            if let existing = fetchTask(id: server.id), existing.updatedAt > server.updatedAt {
                continue
            }
            upsert(server, syncedAt: Date())
        }
        save()
    }

    func markDirty(taskId: UUID) {
        guard let existing = fetchTask(id: taskId) else { return }
        existing.isDirty = true
        save()
    }

    func markDeleted(taskId: UUID) {
        guard let existing = fetchTask(id: taskId) else { return }
        existing.isDeleted = true
        save()
    }

    func purgeTask(id: UUID) {
        if let existing = fetchTask(id: id) {
            context.delete(existing)
            save()
        }
    }

    func replaceTask(id: UUID, with server: TaskItem, syncedAt: Date) {
        if let existing = fetchTask(id: id) {
            context.delete(existing)
        }
        context.insert(LocalTask(task: server, isDirty: false, isDeleted: false, syncedAt: syncedAt))
        save()
    }

    func dirtyTasks() -> [LocalTask] {
        let predicate = #Predicate<LocalTask> { $0.isDirty || $0.isDeleted }
        return (try? context.fetch(FetchDescriptor<LocalTask>(predicate: predicate))) ?? []
    }

    private func fetchTask(id: UUID) -> LocalTask? {
        let predicate = #Predicate<LocalTask> { $0.id == id }
        let all = (try? context.fetch(FetchDescriptor<LocalTask>(predicate: predicate))) ?? []
        return all.first
    }

    // MARK: - Blocks

    func blocks() -> [CalendarBlock] {
        let predicate = #Predicate<LocalBlock> { !$0.isDeleted }
        let all = (try? context.fetch(FetchDescriptor<LocalBlock>(predicate: predicate))) ?? []
        return all.map(\.block).sorted { $0.startAt < $1.startAt }
    }

    func upsert(_ block: CalendarBlock, dirty: Bool = false, deleted: Bool = false, syncedAt: Date? = nil) {
        if let existing = fetchBlock(id: block.id) {
            existing.userId = block.userId
            existing.taskId = block.taskId
            existing.calendarEventId = block.calendarEventId
            existing.title = block.title
            existing.startAt = block.startAt
            existing.endAt = block.endAt
            existing.createdAt = block.createdAt
            existing.updatedAt = block.updatedAt
            existing.isDirty = dirty
            existing.isDeleted = deleted
            existing.syncedAt = syncedAt
        } else {
            context.insert(
                LocalBlock(block: block, isDirty: dirty, isDeleted: deleted, syncedAt: syncedAt)
            )
        }
        save()
    }

    func upsertServerBlocks(_ serverBlocks: [CalendarBlock]) {
        for server in serverBlocks {
            if let existing = fetchBlock(id: server.id), existing.isDirty || existing.isDeleted {
                continue
            }
            if let existing = fetchBlock(id: server.id), existing.updatedAt > server.updatedAt {
                continue
            }
            upsert(server, syncedAt: Date())
        }
        save()
    }

    func markDirty(blockId: UUID) {
        guard let existing = fetchBlock(id: blockId) else { return }
        existing.isDirty = true
        save()
    }

    func markDeleted(blockId: UUID) {
        guard let existing = fetchBlock(id: blockId) else { return }
        existing.isDeleted = true
        save()
    }

    func purgeBlock(id: UUID) {
        if let existing = fetchBlock(id: id) {
            context.delete(existing)
            save()
        }
    }

    func replaceBlock(id: UUID, with server: CalendarBlock, syncedAt: Date) {
        if let existing = fetchBlock(id: id) {
            context.delete(existing)
        }
        context.insert(LocalBlock(block: server, isDirty: false, isDeleted: false, syncedAt: syncedAt))
        save()
    }

    func dirtyBlocks() -> [LocalBlock] {
        let predicate = #Predicate<LocalBlock> { $0.isDirty || $0.isDeleted }
        return (try? context.fetch(FetchDescriptor<LocalBlock>(predicate: predicate))) ?? []
    }

    private func fetchBlock(id: UUID) -> LocalBlock? {
        let predicate = #Predicate<LocalBlock> { $0.id == id }
        let all = (try? context.fetch(FetchDescriptor<LocalBlock>(predicate: predicate))) ?? []
        return all.first
    }

    // MARK: - Sync metadata

    func lastSyncDate() -> Date? {
        metadata(key: "last_synced_at")?.value
    }

    func setLastSyncDate(_ date: Date) {
        setMetadata(key: "last_synced_at", value: date)
    }

    func pendingChangeCount() -> Int {
        dirtyTasks().count + dirtyBlocks().count
    }

    func clearAll() {
        let allTasks = (try? context.fetch(FetchDescriptor<LocalTask>())) ?? []
        for task in allTasks {
            context.delete(task)
        }
        let allBlocks = (try? context.fetch(FetchDescriptor<LocalBlock>())) ?? []
        for block in allBlocks {
            context.delete(block)
        }
        let metadata = (try? context.fetch(FetchDescriptor<SyncMetadata>())) ?? []
        for entry in metadata {
            context.delete(entry)
        }
        save()
    }

    private func metadata(key: String) -> SyncMetadata? {
        let predicate = #Predicate<SyncMetadata> { $0.key == key }
        return (try? context.fetch(FetchDescriptor<SyncMetadata>(predicate: predicate)))?.first
    }

    private func setMetadata(key: String, value: Date?) {
        if let existing = metadata(key: key) {
            existing.value = value
        } else {
            context.insert(SyncMetadata(key: key, value: value))
        }
        save()
    }

    private func save() {
        try? context.save()
    }
}
