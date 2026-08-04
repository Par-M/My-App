import Foundation

struct UserPreference: Codable, Hashable, Sendable {
    var workHoursStart: Int
    var workHoursEnd: Int
    var bufferMinutes: Int
    var energyLevel: Int
    var maxDailyHours: Int
    var defaultDurationMinutes: Int
    var defaultPriority: String

    enum CodingKeys: String, CodingKey {
        case workHoursStart = "work_hours_start"
        case workHoursEnd = "work_hours_end"
        case bufferMinutes = "buffer_minutes"
        case energyLevel = "energy_level"
        case maxDailyHours = "max_daily_hours"
        case defaultDurationMinutes = "default_duration_minutes"
        case defaultPriority = "default_priority"
    }
}

struct UserPreferenceUpdate: Encodable, Sendable {
    var workHoursStart: Int?
    var workHoursEnd: Int?
    var bufferMinutes: Int?
    var energyLevel: Int?
    var maxDailyHours: Int?
    var defaultDurationMinutes: Int?
    var defaultPriority: String?

    init(
        workHoursStart: Int? = nil,
        workHoursEnd: Int? = nil,
        bufferMinutes: Int? = nil,
        energyLevel: Int? = nil,
        maxDailyHours: Int? = nil,
        defaultDurationMinutes: Int? = nil,
        defaultPriority: String? = nil
    ) {
        self.workHoursStart = workHoursStart
        self.workHoursEnd = workHoursEnd
        self.bufferMinutes = bufferMinutes
        self.energyLevel = energyLevel
        self.maxDailyHours = maxDailyHours
        self.defaultDurationMinutes = defaultDurationMinutes
        self.defaultPriority = defaultPriority
    }

    private enum CodingKeys: String, CodingKey {
        case workHoursStart = "work_hours_start"
        case workHoursEnd = "work_hours_end"
        case bufferMinutes = "buffer_minutes"
        case energyLevel = "energy_level"
        case maxDailyHours = "max_daily_hours"
        case defaultDurationMinutes = "default_duration_minutes"
        case defaultPriority = "default_priority"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(workHoursStart, forKey: .workHoursStart)
        try container.encodeIfPresent(workHoursEnd, forKey: .workHoursEnd)
        try container.encodeIfPresent(bufferMinutes, forKey: .bufferMinutes)
        try container.encodeIfPresent(energyLevel, forKey: .energyLevel)
        try container.encodeIfPresent(maxDailyHours, forKey: .maxDailyHours)
        try container.encodeIfPresent(defaultDurationMinutes, forKey: .defaultDurationMinutes)
        try container.encodeIfPresent(defaultPriority, forKey: .defaultPriority)
    }
}
