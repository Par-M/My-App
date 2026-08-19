import Foundation
import SwiftData

@Model
final class LocalTask {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var title: String
    var taskDescription: String?
    var deadline: Date?
    var startAt: Date?
    var endAt: Date?
    var priorityRaw: String
    var statusRaw: String
    var estimatedDuration: Int?
    var actualDuration: Int?
    var productivityRaw: String?
    var startedAt: Date?
    var completedAt: Date?
    var category: String?
    var notes: String?
    var repeatWeekdays: [Int]?
    var beforeTaskIds: [UUID]?
    var afterTaskIds: [UUID]?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var isDeleted: Bool
    var syncedAt: Date?

    init(
        id: UUID,
        userId: UUID,
        title: String,
        taskDescription: String? = nil,
        deadline: Date? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        priority: TaskPriority,
        status: TaskStatus,
        estimatedDuration: Int? = nil,
        actualDuration: Int? = nil,
        productivity: TaskProductivity? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        category: String? = nil,
        notes: String? = nil,
        repeatWeekdays: [Int]? = nil,
        beforeTaskIds: [UUID]? = nil,
        afterTaskIds: [UUID]? = nil,
        isArchived: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        isDirty: Bool = false,
        isDeleted: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.taskDescription = taskDescription
        self.deadline = deadline
        self.startAt = startAt
        self.endAt = endAt
        self.priorityRaw = priority.rawValue
        self.statusRaw = status.rawValue
        self.estimatedDuration = estimatedDuration
        self.actualDuration = actualDuration
        self.productivityRaw = productivity?.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.category = category
        self.notes = notes
        self.repeatWeekdays = repeatWeekdays
        self.beforeTaskIds = beforeTaskIds
        self.afterTaskIds = afterTaskIds
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.isDeleted = isDeleted
        self.syncedAt = syncedAt
    }

    convenience init(task: TaskItem, isDirty: Bool = false, isDeleted: Bool = false, syncedAt: Date? = nil) {
        self.init(
            id: task.id,
            userId: task.userId,
            title: task.title,
            taskDescription: task.description,
            deadline: task.deadline,
            startAt: task.startAt,
            endAt: task.endAt,
            priority: task.priority,
            status: task.status,
            estimatedDuration: task.estimatedDuration,
            actualDuration: task.actualDuration,
            productivity: task.productivity,
            startedAt: task.startedAt,
            completedAt: task.completedAt,
            category: task.category,
            notes: task.notes,
            repeatWeekdays: task.repeatWeekdays,
            beforeTaskIds: task.beforeTaskIds,
            afterTaskIds: task.afterTaskIds,
            isArchived: task.isArchived,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            isDirty: isDirty,
            isDeleted: isDeleted,
            syncedAt: syncedAt
        )
    }

    var taskItem: TaskItem {
        TaskItem(
            id: id,
            userId: userId,
            title: title,
            description: taskDescription,
            deadline: deadline,
            startAt: startAt,
            endAt: endAt,
            priority: TaskPriority(rawValue: priorityRaw) ?? .medium,
            status: TaskStatus(rawValue: statusRaw) ?? .pending,
            estimatedDuration: estimatedDuration,
            actualDuration: actualDuration,
            productivity: TaskProductivity(rawValue: productivityRaw ?? ""),
            startedAt: startedAt,
            completedAt: completedAt,
            category: category,
            notes: notes,
            repeatWeekdays: repeatWeekdays,
            beforeTaskIds: beforeTaskIds,
            afterTaskIds: afterTaskIds,
            isArchived: isArchived,
            progressPercent: 0,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class LocalBlock {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var taskId: UUID
    var calendarEventId: String?
    var title: String
    var startAt: Date
    var endAt: Date
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var isDeleted: Bool
    var syncedAt: Date?

    init(
        id: UUID,
        userId: UUID,
        taskId: UUID,
        calendarEventId: String? = nil,
        title: String,
        startAt: Date,
        endAt: Date,
        createdAt: Date,
        updatedAt: Date,
        isDirty: Bool = false,
        isDeleted: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.taskId = taskId
        self.calendarEventId = calendarEventId
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.isDeleted = isDeleted
        self.syncedAt = syncedAt
    }

    convenience init(block: CalendarBlock, isDirty: Bool = false, isDeleted: Bool = false, syncedAt: Date? = nil) {
        self.init(
            id: block.id,
            userId: block.userId,
            taskId: block.taskId,
            calendarEventId: block.calendarEventId,
            title: block.title,
            startAt: block.startAt,
            endAt: block.endAt,
            createdAt: block.createdAt,
            updatedAt: block.updatedAt,
            isDirty: isDirty,
            isDeleted: isDeleted,
            syncedAt: syncedAt
        )
    }

    var block: CalendarBlock {
        CalendarBlock(
            id: id,
            userId: userId,
            taskId: taskId,
            calendarEventId: calendarEventId,
            title: title,
            startAt: startAt,
            endAt: endAt,
            completedAt: nil,
            completionNote: nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class SyncMetadata {
    @Attribute(.unique) var key: String
    var value: Date?

    init(key: String, value: Date? = nil) {
        self.key = key
        self.value = value
    }
}
