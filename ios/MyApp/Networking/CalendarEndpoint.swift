import Foundation

enum CalendarEndpoint: Endpoint {
    case listBlocks(since: Date? = nil)
    case createBlock(CalendarBlockCreateRequest)
    case updateBlock(id: UUID, request: CalendarBlockUpdateRequest)
    case deleteBlock(UUID)
    case completeBlock(id: UUID, note: String?)
    case reopenBlock(UUID)

    var path: String {
        switch self {
        case .listBlocks, .createBlock:
            return "/api/v1/calendar/blocks"
        case .updateBlock(let id, _):
            return "/api/v1/calendar/blocks/\(id.uuidString.lowercased())"
        case .deleteBlock(let id):
            return "/api/v1/calendar/blocks/\(id.uuidString.lowercased())"
        case .completeBlock(let id, _):
            return "/api/v1/calendar/blocks/\(id.uuidString.lowercased())/complete"
        case .reopenBlock(let id):
            return "/api/v1/calendar/blocks/\(id.uuidString.lowercased())/reopen"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .listBlocks:
            return .get
        case .createBlock:
            return .post
        case .updateBlock:
            return .patch
        case .deleteBlock:
            return .delete
        case .completeBlock, .reopenBlock:
            return .post
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .createBlock(let request):
            return request
        case .updateBlock(_, let request):
            return request
        case .completeBlock(_, let note):
            return CompleteBlockRequest(note: note)
        default:
            return nil
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .listBlocks(let since):
            guard let since else { return nil }
            return [
                URLQueryItem(name: "since", value: JSONCoding.sinceFormatter.string(from: since))
            ]
        default:
            return nil
        }
    }
}
