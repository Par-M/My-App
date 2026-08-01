import Foundation

protocol Endpoint {
    var path: String { get }
    var method: HTTPMethod { get }
    var body: (any Encodable)? { get }
    var requiresAuthentication: Bool { get }
}

extension Endpoint {
    var body: (any Encodable)? { nil }
    var requiresAuthentication: Bool { true }
}
