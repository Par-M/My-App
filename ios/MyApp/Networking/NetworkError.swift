import Foundation

enum NetworkError: Error {
    case invalidResponse
    case unauthorized
    case httpStatus(Int)
    case decoding(Error)
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .httpStatus(let code):
            return "The server returned an error (HTTP \(code))."
        case .decoding:
            return "The server response could not be decoded."
        }
    }
}
