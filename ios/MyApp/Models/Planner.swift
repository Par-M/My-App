import Foundation

struct ScheduledTask: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var priority: TaskPriority
    var status: TaskStatus
    var estimatedDuration: Int?
    var actualDuration: Int?
    var deadline: Date?
    var category: String?
    var start: Date?
    var end: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case priority
        case status
        case estimatedDuration = "estimated_duration"
        case actualDuration = "actual_duration"
        case deadline
        case category
        case start
        case end
    }
}

struct TodayResponse: Codable, Sendable {
    let currentTask: ScheduledTask?
    let priorityTask: ScheduledTask?
    let nextTasks: [ScheduledTask]
    let completedToday: Int
    let focusTimeRemaining: Int
    let dayProgress: Double

    enum CodingKeys: String, CodingKey {
        case currentTask = "current_task"
        case priorityTask = "priority_task"
        case nextTasks = "next_tasks"
        case completedToday = "completed_today"
        case focusTimeRemaining = "focus_time_remaining"
        case dayProgress = "day_progress"
    }
}

struct DailySummaryResponse: Codable, Sendable {
    let date: Date
    let completed: [ScheduledTask]
    let inProgress: [ScheduledTask]
    let pending: [ScheduledTask]
    let hoursWorked: Double
    let tasksRemaining: Int
    let tasksMoved: Int
    let scheduleAdherence: Double

    enum CodingKeys: String, CodingKey {
        case date
        case completed
        case inProgress = "in_progress"
        case pending
        case hoursWorked = "hours_worked"
        case tasksRemaining = "tasks_remaining"
        case tasksMoved = "tasks_moved"
        case scheduleAdherence = "schedule_adherence"
    }
}
