import Foundation

struct CalendarBlock: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let taskId: UUID
    var calendarEventId: String?
    var title: String
    var startAt: Date
    var endAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case taskId = "task_id"
        case calendarEventId = "calendar_event_id"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CalendarBlockListResponse: Codable, Sendable {
    let items: [CalendarBlock]
    let total: Int
}

struct CalendarBlockCreateRequest: Encodable, Sendable {
    let taskId: UUID
    let title: String
    let startAt: Date
    let endAt: Date
    let calendarEventId: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case calendarEventId = "calendar_event_id"
    }
}

struct CalendarBlockUpdateRequest: Encodable, Sendable {
    var title: String?
    var startAt: Date?
    var endAt: Date?
    var calendarEventId: String?

    init(
        title: String? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        calendarEventId: String? = nil
    ) {
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.calendarEventId = calendarEventId
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case calendarEventId = "calendar_event_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(startAt, forKey: .startAt)
        try container.encodeIfPresent(endAt, forKey: .endAt)
        try container.encodeIfPresent(calendarEventId, forKey: .calendarEventId)
    }
}
