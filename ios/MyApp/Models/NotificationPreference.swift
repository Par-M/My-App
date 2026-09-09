import Foundation

struct NotificationPreference: Codable, Sendable {
    var morningBriefingEnabled: Bool
    var morningBriefingTime: String
    var deadlineReminderEnabled: Bool
    var deadlineReminderLeadHours: Int
    var overdueAlertsEnabled: Bool
    var fifteenMinuteReminderEnabled: Bool
    var fifteenMinuteReminderLeadMinutes: Int
    var rescheduleAlertsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case morningBriefingEnabled = "morning_briefing_enabled"
        case morningBriefingTime = "morning_briefing_time"
        case deadlineReminderEnabled = "deadline_reminder_enabled"
        case deadlineReminderLeadHours = "deadline_reminder_lead_hours"
        case overdueAlertsEnabled = "overdue_alerts_enabled"
        case rescheduleAlertsEnabled = "reschedule_alerts_enabled"
        case fifteenMinuteReminderEnabled = "fifteen_minute_reminder_enabled"
        case fifteenMinuteReminderLeadMinutes = "fifteen_minute_reminder_lead_minutes"
    }
}

struct NotificationPreferenceUpdate: Encodable, Sendable {
    var morningBriefingEnabled: Bool?
    var morningBriefingTime: String?
    var deadlineReminderEnabled: Bool?
    var deadlineReminderLeadHours: Int?
    var overdueAlertsEnabled: Bool?
    var fifteenMinuteReminderEnabled: Bool?
    var fifteenMinuteReminderLeadMinutes: Int?
    var rescheduleAlertsEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case morningBriefingEnabled = "morning_briefing_enabled"
        case morningBriefingTime = "morning_briefing_time"
        case deadlineReminderEnabled = "deadline_reminder_enabled"
        case deadlineReminderLeadHours = "deadline_reminder_lead_hours"
        case overdueAlertsEnabled = "overdue_alerts_enabled"
        case rescheduleAlertsEnabled = "reschedule_alerts_enabled"
        case fifteenMinuteReminderEnabled = "fifteen_minute_reminder_enabled"
        case fifteenMinuteReminderLeadMinutes = "fifteen_minute_reminder_lead_minutes"
    }
}

struct DeviceRegisterRequest: Encodable, Sendable {
    let deviceId: String
    let token: String
    let platform: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case token
        case platform
        case timezone
    }
}

struct DeviceTokenResponse: Codable, Sendable {
    let deviceId: String
    let token: String
    let platform: String
    let timezone: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case token
        case platform
        case timezone
        case isActive = "is_active"
    }
}
