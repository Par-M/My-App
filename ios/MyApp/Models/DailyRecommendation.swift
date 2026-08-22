import Foundation

struct RecommendedPart: Codable, Identifiable, Hashable, Sendable {
    let taskId: UUID
    let taskTitle: String
    let partTitle: String?
    let partIndex: Int
    let partCount: Int
    let minutes: Int
    let priority: TaskPriority
    let deadline: Date?
    let isOverdue: Bool
    let reason: String

    var id: String {
        "\(taskId.uuidString)-\(partIndex)"
    }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case taskTitle = "task_title"
        case partTitle = "part_title"
        case partIndex = "part_index"
        case partCount = "part_count"
        case minutes
        case priority
        case deadline
        case isOverdue = "is_overdue"
        case reason
    }
}

struct UnscheduledPart: Codable, Identifiable, Hashable, Sendable {
    let taskId: UUID
    let taskTitle: String
    let partTitle: String?
    let minutes: Int
    let priority: TaskPriority

    var id: String { "\(taskId.uuidString)-\(partTitle ?? "")" }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case taskTitle = "task_title"
        case partTitle = "part_title"
        case minutes
        case priority
    }
}

struct DayRecommendation: Codable, Identifiable, Hashable, Sendable {
    let date: Date
    let availableMinutes: Int
    let items: [RecommendedPart]

    var id: String { date.formatted(.iso8601.year().month().day()) }

    enum CodingKeys: String, CodingKey {
        case date
        case availableMinutes = "available_minutes"
        case items
    }
}

struct DailyRecommendationsResponse: Codable, Sendable {
    let days: [DayRecommendation]
    let unscheduled: [UnscheduledPart]
}

struct DailyRecommendationsRequest: Encodable, Sendable {
    let timezone: String
    let startDate: Date?
    let endDate: Date?
    var busyTimes: [BusyTimeRequest]

    enum CodingKeys: String, CodingKey {
        case timezone
        case startDate = "start_date"
        case endDate = "end_date"
        case busyTimes = "busy_times"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timezone, forKey: .timezone)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(busyTimes, forKey: .busyTimes)
    }
}

struct BreakdownPartItem: Codable, Identifiable, Hashable, Sendable {
    let index: Int
    let title: String
    let minutes: Int

    var id: Int { index }
}

struct BreakdownResponse: Codable, Sendable {
    let taskId: UUID
    let taskTitle: String
    let parts: [BreakdownPartItem]
    let source: String

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case taskTitle = "task_title"
        case parts
        case source
    }
}
