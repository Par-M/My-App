import Foundation

struct FocusSession: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let taskID: UUID?
    let durationSeconds: Int
    let startedAt: Date
    let endedAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case durationSeconds = "duration_seconds"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
    }
}

struct FocusSessionCreate: Encodable, Sendable {
    let taskID: UUID?
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int?

    init(
        taskID: UUID?,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int? = nil
    ) {
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
    }
}

struct FocusSummary: Codable, Hashable, Sendable {
    let totalDurationSeconds: Int
    let sessionCount: Int
    let taskID: UUID?
    let analysis: String?
    let dateStarted: Date?
    let dateEnded: Date?

    enum CodingKeys: String, CodingKey {
        case totalDurationSeconds = "total_duration_seconds"
        case sessionCount = "session_count"
        case taskID = "task_id"
        case analysis
        case dateStarted = "date_started"
        case dateEnded = "date_ended"
    }
}
