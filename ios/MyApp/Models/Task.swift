import Foundation

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: "Pending"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        }
    }
}

enum TaskProductivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast
    case moderate
    case slow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fast: "Fast"
        case .moderate: "Moderate"
        case .slow: "Slow"
        }
    }
}

struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    var title: String
    var description: String?
    var deadline: Date?
    var startAt: Date?
    var endAt: Date?
    var priority: TaskPriority
    var status: TaskStatus
    var estimatedDuration: Int?
    var actualDuration: Int?
    var productivity: TaskProductivity?
    var startedAt: Date?
    var completedAt: Date?
    var category: String?
    var notes: String?
    var repeatWeekdays: [Int]?
    var repeatEndsOn: Date?
    var beforeTaskIds: [UUID]?
    var afterTaskIds: [UUID]?
    var isArchived: Bool
    var progressPercent: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case deadline
        case startAt = "start_at"
        case endAt = "end_at"
        case priority
        case status
        case estimatedDuration = "estimated_duration"
        case actualDuration = "actual_duration"
        case productivity
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case category
        case notes
        case repeatWeekdays = "repeat_weekdays"
        case repeatEndsOn = "repeat_ends_on"
        case beforeTaskIds = "before_task_ids"
        case afterTaskIds = "after_task_ids"
        case isArchived = "is_archived"
        case progressPercent = "progress_percent"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TaskListResponse: Codable, Sendable {
    let items: [TaskItem]
    let total: Int
}

struct TaskCreateRequest: Codable, Sendable {
    let title: String
    let description: String?
    let deadline: Date?
    let startAt: Date?
    let endAt: Date?
    let priority: TaskPriority
    let status: TaskStatus
    let estimatedDuration: Int?
    let category: String?
    let notes: String?
    let repeatWeekdays: [Int]?
    let repeatEndsOn: Date?
    let beforeTaskIds: [UUID]?
    let afterTaskIds: [UUID]?

    init(
        title: String,
        description: String?,
        deadline: Date?,
        startAt: Date?,
        endAt: Date?,
        priority: TaskPriority,
        status: TaskStatus,
        estimatedDuration: Int?,
        category: String?,
        notes: String?,
        repeatWeekdays: [Int]?,
        beforeTaskIds: [UUID]? = nil,
        afterTaskIds: [UUID]? = nil,
        repeatEndsOn: Date? = nil
    ) {
        self.title = title
        self.description = description
        self.deadline = deadline
        self.startAt = startAt
        self.endAt = endAt
        self.priority = priority
        self.status = status
        self.estimatedDuration = estimatedDuration
        self.category = category
        self.notes = notes
        self.repeatWeekdays = repeatWeekdays
        self.beforeTaskIds = beforeTaskIds
        self.afterTaskIds = afterTaskIds
        self.repeatEndsOn = repeatEndsOn
    }

    init(from local: LocalTask) {
        title = local.title
        description = local.taskDescription
        deadline = local.deadline
        startAt = local.startAt
        endAt = local.endAt
        priority = TaskPriority(rawValue: local.priorityRaw) ?? .medium
        status = TaskStatus(rawValue: local.statusRaw) ?? .pending
        estimatedDuration = local.estimatedDuration
        category = local.category
        notes = local.notes
        repeatWeekdays = local.repeatWeekdays
        beforeTaskIds = local.beforeTaskIds
        afterTaskIds = local.afterTaskIds
        repeatEndsOn = local.repeatEndsOn
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case deadline
        case startAt = "start_at"
        case endAt = "end_at"
        case priority
        case status
        case estimatedDuration = "estimated_duration"
        case category
        case notes
        case repeatWeekdays = "repeat_weekdays"
        case repeatEndsOn = "repeat_ends_on"
        case beforeTaskIds = "before_task_ids"
        case afterTaskIds = "after_task_ids"
    }
}

struct TaskUpdateRequest: Encodable, Sendable {
    let title: String
    let description: String?
    let deadline: Date?
    let startAt: Date?
    let endAt: Date?
    let priority: TaskPriority
    let status: TaskStatus
    let estimatedDuration: Int?
    let category: String?
    let notes: String?
    let repeatWeekdays: [Int]?
    let repeatEndsOn: Date?
    let beforeTaskIds: [UUID]?
    let afterTaskIds: [UUID]?

    init(task: TaskItem) {
        title = task.title
        description = task.description
        deadline = task.deadline
        startAt = task.startAt
        endAt = task.endAt
        priority = task.priority
        status = task.status
        estimatedDuration = task.estimatedDuration
        category = task.category
        notes = task.notes
        repeatWeekdays = task.repeatWeekdays
        repeatEndsOn = task.repeatEndsOn
        beforeTaskIds = task.beforeTaskIds
        afterTaskIds = task.afterTaskIds
    }

    init(from local: LocalTask) {
        title = local.title
        description = local.taskDescription
        deadline = local.deadline
        startAt = local.startAt
        endAt = local.endAt
        priority = TaskPriority(rawValue: local.priorityRaw) ?? .medium
        status = TaskStatus(rawValue: local.statusRaw) ?? .pending
        estimatedDuration = local.estimatedDuration
        category = local.category
        notes = local.notes
        repeatWeekdays = local.repeatWeekdays
        repeatEndsOn = local.repeatEndsOn
        beforeTaskIds = local.beforeTaskIds
        afterTaskIds = local.afterTaskIds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(priority, forKey: .priority)
        try container.encode(status, forKey: .status)
        try container.encode(estimatedDuration, forKey: .estimatedDuration)
        try container.encode(category, forKey: .category)
        try container.encode(notes, forKey: .notes)
        try container.encode(repeatWeekdays, forKey: .repeatWeekdays)
        try container.encode(repeatEndsOn, forKey: .repeatEndsOn)
        try container.encodeIfPresent(beforeTaskIds, forKey: .beforeTaskIds)
        try container.encodeIfPresent(afterTaskIds, forKey: .afterTaskIds)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case deadline
        case startAt = "start_at"
        case endAt = "end_at"
        case priority
        case status
        case estimatedDuration = "estimated_duration"
        case category
        case notes
        case repeatWeekdays = "repeat_weekdays"
        case repeatEndsOn = "repeat_ends_on"
        case beforeTaskIds = "before_task_ids"
        case afterTaskIds = "after_task_ids"
    }
}

struct CompleteTaskRequest: Encodable, Sendable {
    let actualMinutes: Int?
    let productivity: TaskProductivity?

    private enum CodingKeys: String, CodingKey {
        case actualMinutes = "actual_minutes"
        case productivity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(actualMinutes, forKey: .actualMinutes)
        try container.encodeIfPresent(productivity, forKey: .productivity)
    }
}

struct RecordTimeRequest: Encodable, Sendable {
    let minutes: Int

    private enum CodingKeys: String, CodingKey {
        case minutes = "actual_duration"
    }
}

struct SnoozeRequest: Encodable, Sendable {
    let minutes: Int
    let timezone: String
}

struct SnoozeResponse: Codable, Sendable {
    let task: TaskItem
    let blocks: [CalendarBlock]
}

struct RescheduleRequest: Encodable, Sendable {
    let minutesRemaining: Int
    let reason: String?
    let timezone: String

    private enum CodingKeys: String, CodingKey {
        case minutesRemaining = "minutes_remaining"
        case reason
        case timezone
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minutesRemaining, forKey: .minutesRemaining)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(timezone, forKey: .timezone)
    }
}

struct RescheduleResponse: Codable, Sendable {
    let task: TaskItem
    let blocks: [CalendarBlock]
}
