import Foundation

enum CalendarEndpoint: Endpoint {
    case listBlocks
    case createBlock(CalendarBlockCreateRequest)
    case updateBlock(id: UUID, request: CalendarBlockUpdateRequest)
    case deleteBlock(UUID)

    var path: String {
        switch self {
        case .listBlocks, .createBlock:
            return "/api/v1/calendar/blocks"
        case .updateBlock(let id, _):
            return "/api/v1/calendar/blocks/\(id.uuidString.lowercased())"
        case .deleteBlock(let id):
            return "/api/v1/calendar/blocks/\(id.uuidString.lowercased())"
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
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .createBlock(let request):
            return request
        case .updateBlock(_, let request):
            return request
        default:
            return nil
        }
    }
}
