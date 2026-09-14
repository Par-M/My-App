import Foundation

enum HabitEndpoint: Endpoint {
    case create(HabitCreateRequest)
    case update(id: UUID, request: HabitUpdateRequest)
    case delete(UUID)
    case log(id: UUID, count: Int, date: Date?)
    case setDay(id: UUID, count: Int, date: Date?)
    case dashboard
    case reorder(habitIds: [UUID])

    var path: String {
        switch self {
        case .create:
            return "/api/v1/habits"
        case .update(let id, _):
            return "/api/v1/habits/\(id.uuidString.lowercased())"
        case .delete(let id):
            return "/api/v1/habits/\(id.uuidString.lowercased())"
        case .log(let id, _, _):
            return "/api/v1/habits/\(id.uuidString.lowercased())/logs"
        case .setDay(let id, _, _):
            return "/api/v1/habits/\(id.uuidString.lowercased())/logs/day"
        case .dashboard:
            return "/api/v1/habits/dashboard"
        case .reorder:
            return "/api/v1/habits/reorder"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .dashboard:
            return .get
        case .create, .log, .reorder:
            return .post
        case .setDay:
            return .put
        case .update:
            return .patch
        case .delete:
            return .delete
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .create(let request):
            return request
        case .update(_, let request):
            return request
        case .log(_, let count, let date):
            return HabitLogCreateRequest(count: count, date: date)
        case .setDay(_, let count, let date):
            return HabitDaySetRequest(count: count, date: date)
        case .reorder(let habitIds):
            return HabitReorderRequest(habitIds: habitIds)
        default:
            return nil
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .dashboard, .setDay:
            return [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
        default:
            return nil
        }
    }
}
