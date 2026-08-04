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

struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    var title: String
    var description: String?
    var deadline: Date?
    var priority: TaskPriority
    var status: TaskStatus
    var estimatedDuration: Int?
    var actualDuration: Int?
    var startedAt: Date?
    var completedAt: Date?
    var category: String?
    var notes: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case deadline
        case priority
        case status
        case estimatedDuration = "estimated_duration"
        case actualDuration = "actual_duration"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case category
        case notes
        case isArchived = "is_archived"
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
    let priority: TaskPriority
    let status: TaskStatus
    let estimatedDuration: Int?
    let category: String?
    let notes: String?

    init(
        title: String,
        description: String?,
        deadline: Date?,
        priority: TaskPriority,
        status: TaskStatus,
        estimatedDuration: Int?,
        category: String?,
        notes: String?
    ) {
        self.title = title
        self.description = description
        self.deadline = deadline
        self.priority = priority
        self.status = status
        self.estimatedDuration = estimatedDuration
        self.category = category
        self.notes = notes
    }

    init(from local: LocalTask) {
        title = local.title
        description = local.taskDescription
        deadline = local.deadline
        priority = TaskPriority(rawValue: local.priorityRaw) ?? .medium
        status = TaskStatus(rawValue: local.statusRaw) ?? .pending
        estimatedDuration = local.estimatedDuration
        category = local.category
        notes = local.notes
    }
}

struct TaskUpdateRequest: Encodable, Sendable {
    let title: String
    let description: String?
    let deadline: Date?
    let priority: TaskPriority
    let status: TaskStatus
    let estimatedDuration: Int?
    let category: String?
    let notes: String?

    init(task: TaskItem) {
        title = task.title
        description = task.description
        deadline = task.deadline
        priority = task.priority
        status = task.status
        estimatedDuration = task.estimatedDuration
        category = task.category
        notes = task.notes
    }

    init(from local: LocalTask) {
        title = local.title
        description = local.taskDescription
        deadline = local.deadline
        priority = TaskPriority(rawValue: local.priorityRaw) ?? .medium
        status = TaskStatus(rawValue: local.statusRaw) ?? .pending
        estimatedDuration = local.estimatedDuration
        category = local.category
        notes = local.notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(priority, forKey: .priority)
        try container.encode(status, forKey: .status)
        try container.encode(estimatedDuration, forKey: .estimatedDuration)
        try container.encode(category, forKey: .category)
        try container.encode(notes, forKey: .notes)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case deadline
        case priority
        case status
        case estimatedDuration = "estimated_duration"
        case category
        case notes
    }
}

struct CompleteTaskRequest: Encodable, Sendable {
    let actualMinutes: Int?
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
