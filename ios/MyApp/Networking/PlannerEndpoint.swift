import Foundation

enum PlannerEndpoint: Endpoint {
    case today(timezone: String)
    case dailySummary(timezone: String)

    var path: String {
        switch self {
        case .today:
            return "/api/v1/today"
        case .dailySummary:
            return "/api/v1/daily-summary"
        }
    }

    var method: HTTPMethod {
        .get
    }

    var body: (any Encodable)? {
        nil
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .today(let timezone), .dailySummary(let timezone):
            return [URLQueryItem(name: "timezone", value: timezone)]
        }
    }
}
