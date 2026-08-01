import Foundation

struct User: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let email: String?
    let name: String?
    let provider: String
}
