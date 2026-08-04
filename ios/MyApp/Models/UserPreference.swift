import Foundation

struct UserPreference: Codable, Hashable, Sendable {
    var workHoursStart: Int
    var workHoursEnd: Int
    var bufferMinutes: Int
    var energyLevel: Int

    enum CodingKeys: String, CodingKey {
        case workHoursStart = "work_hours_start"
        case workHoursEnd = "work_hours_end"
        case bufferMinutes = "buffer_minutes"
        case energyLevel = "energy_level"
    }
}

struct UserPreferenceUpdate: Encodable, Sendable {
    var workHoursStart: Int?
    var workHoursEnd: Int?
    var bufferMinutes: Int?
    var energyLevel: Int?

    init(
        workHoursStart: Int? = nil,
        workHoursEnd: Int? = nil,
        bufferMinutes: Int? = nil,
        energyLevel: Int? = nil
    ) {
        self.workHoursStart = workHoursStart
        self.workHoursEnd = workHoursEnd
        self.bufferMinutes = bufferMinutes
        self.energyLevel = energyLevel
    }

    private enum CodingKeys: String, CodingKey {
        case workHoursStart = "work_hours_start"
        case workHoursEnd = "work_hours_end"
        case bufferMinutes = "buffer_minutes"
        case energyLevel = "energy_level"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(workHoursStart, forKey: .workHoursStart)
        try container.encodeIfPresent(workHoursEnd, forKey: .workHoursEnd)
        try container.encodeIfPresent(bufferMinutes, forKey: .bufferMinutes)
        try container.encodeIfPresent(energyLevel, forKey: .energyLevel)
    }
}
