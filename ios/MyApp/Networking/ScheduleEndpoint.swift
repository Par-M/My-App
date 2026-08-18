import Foundation

struct BusyTimeRequest: Encodable, Sendable {
    let start: Date
    let end: Date
}

struct ScheduleGenerateRequest: Encodable, Sendable {
    let startDate: Date
    let endDate: Date
    let timezone: String
    var busyTimes: [BusyTimeRequest]
    var taskIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case timezone
        case busyTimes = "busy_times"
        case taskIds = "task_ids"
    }
}

enum ScheduleEndpoint: Endpoint {
    case generate(ScheduleGenerateRequest)
    case replan(ScheduleGenerateRequest)
    case listRecommendations(status: RecommendationStatus?)
    case accept(UUID)
    case reject(UUID)
    case acceptItem(recommendationID: UUID, itemIndex: Int)
    case redoItem(recommendationID: UUID, itemIndex: Int)

    var path: String {
        switch self {
        case .generate:
            return "/api/v1/schedule/generate"
        case .replan:
            return "/api/v1/schedule/replan"
        case .listRecommendations:
            return "/api/v1/schedule/recommendations"
        case .accept(let id):
            return "/api/v1/schedule/recommendations/\(id.uuidString.lowercased())/accept"
        case .reject(let id):
            return "/api/v1/schedule/recommendations/\(id.uuidString.lowercased())/reject"
        case .acceptItem(let id, let index):
            return "/api/v1/schedule/recommendations/\(id.uuidString.lowercased())/items/\(index)/accept"
        case .redoItem(let id, let index):
            return "/api/v1/schedule/recommendations/\(id.uuidString.lowercased())/items/\(index)/redo"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .listRecommendations:
            return .get
        case .generate, .replan, .accept, .reject, .acceptItem, .redoItem:
            return .post
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .generate(let request), .replan(let request):
            return request
        default:
            return nil
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .listRecommendations(let status):
            if let status {
                return [URLQueryItem(name: "status", value: status.rawValue)]
            }
            return nil
        default:
            return nil
        }
    }
}
