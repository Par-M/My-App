import Foundation

enum TaskEndpoint: Endpoint {
    case list(
        search: String?,
        priority: TaskPriority?,
        status: TaskStatus?,
        category: String?,
        archived: Bool,
        sort: String?,
        order: String,
        since: Date? = nil
    )
    case create(TaskCreateRequest)
    case parse(TaskParseRequest)
    case update(id: UUID, request: TaskUpdateRequest)
    case delete(UUID)
    case archive(UUID)
    case restore(UUID)
    case start(UUID)
    case complete(id: UUID, minutes: Int?, productivity: TaskProductivity?)
    case recordTime(id: UUID, minutes: Int)
    case overdue
    case reschedule(id: UUID, minutes: Int, reason: String?, timezone: String, deadline: Date?)
    case occurrence(id: UUID, request: OccurrenceUpdateRequest)

    var path: String {
        switch self {
        case .list:
            return "/api/v1/tasks"
        case .create:
            return "/api/v1/tasks"
        case .parse:
            return "/api/v1/tasks/parse"
        case .update(let id, _):
            return "/api/v1/tasks/\(id.uuidString.lowercased())"
        case .delete(let id):
            return "/api/v1/tasks/\(id.uuidString.lowercased())"
        case .archive(let id):
            return "/api/v1/tasks/\(id.uuidString.lowercased())/archive"
        case .restore(let id):
            return "/api/v1/tasks/\(id.uuidString.lowercased())/restore"
        case .start(let id):
            return "/api/v1/tasks/\(id.uuidString.lowercased())/start"
        case .complete(let id, _, _):
            return "/api/v1/tasks/\(id.uuidString.lowercased())/complete"
        case .recordTime(let id, _):
            return "/api/v1/tasks/\(id.uuidString.lowercased())"
        case .overdue:
            return "/api/v1/tasks/overdue"
        case .reschedule(let id, _, _, _, _):
            return "/api/v1/tasks/\(id.uuidString.lowercased())/reschedule"
        case .occurrence(let id, _):
            return "/api/v1/tasks/\(id.uuidString.lowercased())/occurrence"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .list, .overdue:
            return .get
        case .create:
            return .post
        case .parse:
            return .post
        case .update, .recordTime, .occurrence:
            return .patch
        case .delete:
            return .delete
        case .archive, .restore, .start, .complete, .reschedule:
            return .post
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .create(let request):
            return request
        case .parse(let request):
            return request
        case .update(_, let request):
            return request
        case .complete(_, let minutes, let productivity):
            return CompleteTaskRequest(actualMinutes: minutes, productivity: productivity)
        case .recordTime(_, let minutes):
            return RecordTimeRequest(minutes: minutes)
        case .reschedule(_, let minutes, let reason, let timezone, let deadline):
            return RescheduleRequest(
                minutesRemaining: minutes,
                reason: reason,
                timezone: timezone,
                deadline: deadline
            )
        case .occurrence(_, let request):
            return request
        default:
            return nil
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .list(let search, let priority, let status, let category, let archived, let sort, let order, let since):
            var items: [URLQueryItem] = []
            if let search, !search.isEmpty {
                items.append(URLQueryItem(name: "search", value: search))
            }
            if let priority {
                items.append(URLQueryItem(name: "priority", value: priority.rawValue))
            }
            if let status {
                items.append(URLQueryItem(name: "status", value: status.rawValue))
            }
            if let category, !category.isEmpty {
                items.append(URLQueryItem(name: "category", value: category))
            }
            if archived {
                items.append(URLQueryItem(name: "archived", value: "true"))
            }
            if let sort {
                items.append(URLQueryItem(name: "sort", value: sort))
            }
            if order != "asc" {
                items.append(URLQueryItem(name: "order", value: order))
            }
            if let since {
                items.append(
                    URLQueryItem(name: "since", value: JSONCoding.sinceFormatter.string(from: since))
                )
            }
            return items.isEmpty ? nil : items
        default:
            return nil
        }
    }
}
