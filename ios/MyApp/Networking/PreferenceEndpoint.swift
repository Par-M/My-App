import Foundation

enum PreferenceEndpoint: Endpoint {
    case get
    case update(UserPreferenceUpdate)

    var path: String {
        "/api/v1/preferences"
    }

    var method: HTTPMethod {
        switch self {
        case .get:
            return .get
        case .update:
            return .put
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .update(let request):
            return request
        case .get:
            return nil
        }
    }
}
