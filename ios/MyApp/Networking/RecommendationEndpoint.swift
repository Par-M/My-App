import Foundation

enum RecommendationEndpoint: Endpoint {
    case daily(DailyRecommendationsRequest)
    case breakdown(taskID: UUID)

    var path: String {
        switch self {
        case .daily:
            return "/api/v1/recommendations/daily"
        case .breakdown(let id):
            return "/api/v1/recommendations/breakdown/\(id.uuidString.lowercased())"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .daily, .breakdown:
            return .post
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .daily(let request):
            return request
        case .breakdown:
            return nil
        }
    }
}
