import Foundation

struct Habit: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    var title: String
    var repeatWeekdays: [Int]?
    var dailyGoal: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case repeatWeekdays = "repeat_weekdays"
        case dailyGoal = "daily_goal"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct HabitListResponse: Codable, Sendable {
    let items: [Habit]
    let total: Int
}

struct HabitCreateRequest: Encodable, Sendable {
    let title: String
    let repeatWeekdays: [Int]?
    let dailyGoal: Int

    init(title: String, repeatWeekdays: [Int]?, dailyGoal: Int) {
        self.title = title
        self.repeatWeekdays = repeatWeekdays
        self.dailyGoal = dailyGoal
    }

    init(from habit: Habit) {
        title = habit.title
        repeatWeekdays = habit.repeatWeekdays
        dailyGoal = habit.dailyGoal
    }
}

struct HabitUpdateRequest: Encodable, Sendable {
    let title: String?
    let repeatWeekdays: [Int]?
    let dailyGoal: Int?

    init(title: String? = nil, repeatWeekdays: [Int]? = nil, dailyGoal: Int? = nil) {
        self.title = title
        self.repeatWeekdays = repeatWeekdays
        self.dailyGoal = dailyGoal
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(repeatWeekdays, forKey: .repeatWeekdays)
        try container.encode(dailyGoal, forKey: .dailyGoal)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case repeatWeekdays = "repeat_weekdays"
        case dailyGoal = "daily_goal"
    }
}

struct HabitLogCreateRequest: Encodable, Sendable {
    let count: Int
    let date: Date?

    init(count: Int, date: Date? = nil) {
        self.count = count
        self.date = date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(count, forKey: .count)
        if let date {
            try container.encode(JSONCoding.dayFormatter.string(from: date), forKey: .date)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case date
    }
}

struct HabitLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let habitId: UUID
    let count: Int
    let completedAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case habitId = "habit_id"
        case count
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}

struct HabitDayStats: Codable, Hashable, Sendable {
    let date: Date
    let scheduled: Bool
    let completedCount: Int

    enum CodingKeys: String, CodingKey {
        case date
        case scheduled
        case completedCount = "completed_count"
    }
}

struct HabitStats: Codable, Identifiable, Hashable, Sendable {
    let habit: Habit
    let currentStreak: Int
    let bestStreak: Int
    let completionRate7d: Double
    let completionRate30d: Double
    let scheduled7d: Int
    let completed7d: Int
    let totalCompletions: Int
    let last7Days: [HabitDayStats]

    var id: UUID { habit.id }

    enum CodingKeys: String, CodingKey {
        case habit
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case completionRate7d = "completion_rate_7d"
        case completionRate30d = "completion_rate_30d"
        case scheduled7d = "scheduled_7d"
        case completed7d = "completed_7d"
        case totalCompletions = "total_completions"
        case last7Days = "last_7_days"
    }
}

struct HabitDashboard: Codable, Hashable, Sendable {
    let habits: [HabitStats]
}

extension Habit {
    var scheduleLabel: String {
        guard let weekdays = repeatWeekdays, !weekdays.isEmpty else {
            return "Every day"
        }
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return weekdays.sorted().map { letters[$0] }.joined(separator: ", ")
    }
}

extension HabitStats {
    var today: HabitDayStats? {
        last7Days.last
    }

    var isDoneToday: Bool {
        guard let today else { return false }
        return today.completedCount >= habit.dailyGoal
    }
}
