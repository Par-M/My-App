import Foundation

enum RecommendationEndpoint: Endpoint {
    case daily(DailyRecommendationsRequest)

    var path: String {
        switch self {
        case .daily:
            return "/api/v1/recommendations/daily"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .daily:
            return .post
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .daily(let request):
            return request
        }
    }
}
