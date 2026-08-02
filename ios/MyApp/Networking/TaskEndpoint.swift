import Foundation

enum TaskEndpoint: Endpoint {
    case list(
        search: String?,
        priority: TaskPriority?,
        status: TaskStatus?,
        category: String?,
        archived: Bool,
        sort: String?,
        order: String
    )
    case create(TaskCreateRequest)
    case get(UUID)
    case update(id: UUID, request: TaskUpdateRequest)
    case delete(UUID)
    case archive(UUID)
    case restore(UUID)

    var path: String {
        switch self {
        case .list:
            return "/api/v1/tasks"
        case .create:
            return "/api/v1/tasks"
        case .get(let id):
            return "/api/v1/tasks/\(id.uuidString.lowercased())"
        case .update(let id, _):
            return "/api/v1/tasks/\(id.uuidString.lowercased())"
        case .delete(let id):
            return "/api/v1/tasks/\(id.uuidString.lowercased())"
        case .archive(let id):
            return "/api/v1/tasks/\(id.uuidString.lowercased())/archive"
        case .restore(let id):
            return "/api/v1/tasks/\(id.uuidString.lowercased())/restore"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .list, .get:
            return .get
        case .create:
            return .post
        case .update:
            return .patch
        case .delete:
            return .delete
        case .archive, .restore:
            return .post
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .create(let request):
            return request
        case .update(_, let request):
            return request
        default:
            return nil
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .list(let search, let priority, let status, let category, let archived, let sort, let order):
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
            return items.isEmpty ? nil : items
        default:
            return nil
        }
    }
}
