import Foundation

enum FocusEndpoint: Endpoint {
    case sessions
    case summary(after: Date?, before: Date?)
    case create(FocusSessionCreate)
    case reflections
    case createReflection(ReflectionCreate)
    case analysis(UUID)

    var path: String {
        switch self {
        case .sessions, .create:
            return "/api/v1/focus/sessions"
        case .summary:
            return "/api/v1/focus/summary"
        case .reflections, .createReflection:
            return "/api/v1/reflections"
        case .analysis(let id):
            return "/api/v1/reflections/\(id.uuidString.lowercased())/analysis"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .sessions, .summary, .reflections:
            return .get
        case .create, .createReflection, .analysis:
            return .post
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .create(let payload):
            return payload
        case .createReflection(let payload):
            return payload
        default:
            return nil
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .summary(let after, let before):
            var items: [URLQueryItem] = []
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let after {
                items.append(URLQueryItem(name: "after", value: formatter.string(from: after)))
            }
            if let before {
                items.append(URLQueryItem(name: "before", value: formatter.string(from: before)))
            }
            return items.isEmpty ? nil : items
        default:
            return nil
        }
    }
}
