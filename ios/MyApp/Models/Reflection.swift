import Foundation

struct MorningMessage: Codable, Hashable, Sendable {
    let message: String
    let date: Date
}
