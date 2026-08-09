import Foundation

enum RecommendationStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case accepted
    case rejected
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: "Pending"
        case .accepted: "Accepted"
        case .rejected: "Rejected"
        case .failed: "Failed"
        }
    }
}

struct ScheduleItem: Codable, Identifiable, Hashable, Sendable {
    let taskId: UUID
    let taskTitle: String
    let start: Date
    let end: Date
    let reason: String
    let accepted: Bool

    var id: String {
        "\(taskId)-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
    }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case taskTitle = "task_title"
        case start
        case end
        case reason
        case accepted
    }
}

struct ScheduleTimeSlot: Codable, Hashable, Sendable {
    let start: Date
    let end: Date
}

struct ScheduleMeta: Codable, Hashable, Sendable {
    var overcommitted: Bool
    var risk: String?
    var deferredTasks: [String]
    var freeSlots: [ScheduleTimeSlot]
    var scheduleableHours: Double
    var requiredHours: Double
    var provider: String?
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case overcommitted
        case risk
        case deferredTasks = "deferred_tasks"
        case freeSlots = "free_slots"
        case scheduleableHours = "scheduleable_hours"
        case requiredHours = "required_hours"
        case provider
        case warnings
    }

    static let empty = ScheduleMeta(
        overcommitted: false,
        risk: nil,
        deferredTasks: [],
        freeSlots: [],
        scheduleableHours: 0,
        requiredHours: 0,
        provider: nil,
        warnings: []
    )
}

struct RecommendationResponse: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var status: RecommendationStatus
    var accepted: Bool
    var reasoning: String?
    var items: [ScheduleItem]
    var meta: ScheduleMeta
    var failureReason: String?
    var retryAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case accepted
        case reasoning
        case items
        case meta
        case failureReason = "failure_reason"
        case retryAt = "retry_at"
        case createdAt = "created_at"
    }
}

struct ScheduleProposal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var status: RecommendationStatus
    var accepted: Bool
    var reasoning: String?
    var items: [ScheduleItem]
    var meta: ScheduleMeta
    var failureReason: String?
    var retryAt: Date?
    var createdAt: Date
    var message: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case accepted
        case reasoning
        case items
        case meta
        case failureReason = "failure_reason"
        case retryAt = "retry_at"
        case createdAt = "created_at"
        case message
    }
}

struct AcceptResponse: Codable, Sendable {
    let recommendation: RecommendationResponse
    let blocks: [CalendarBlock]
}

struct RecommendationListResponse: Codable, Sendable {
    let items: [RecommendationResponse]
    let total: Int
}
