import Foundation

struct Reflection: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let date: Date
    let text: String
    let analysis: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case text
        case analysis
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ReflectionCreate: Encodable, Sendable {
    let date: Date
    let text: String
}

struct ReflectionAnalysisResponse: Codable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let date: Date
    let analysis: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case analysis
    }
}
