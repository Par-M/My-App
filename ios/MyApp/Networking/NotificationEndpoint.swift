import Foundation

enum NotificationEndpoint: Endpoint {
    case getPreferences
    case updatePreferences(NotificationPreferenceUpdate)
    case registerDevice(DeviceRegisterRequest)
    case unregisterDevice(String)

    var path: String {
        switch self {
        case .getPreferences, .updatePreferences:
            return "/api/v1/notifications/preferences"
        case .registerDevice:
            return "/api/v1/devices/register"
        case .unregisterDevice(let deviceId):
            return "/api/v1/devices/\(deviceId)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getPreferences:
            return .get
        case .updatePreferences:
            return .patch
        case .registerDevice:
            return .post
        case .unregisterDevice:
            return .delete
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .updatePreferences(let request):
            return request
        case .registerDevice(let request):
            return request
        default:
            return nil
        }
    }
}
