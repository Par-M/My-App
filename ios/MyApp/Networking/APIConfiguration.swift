import Foundation

enum APIConfiguration {
    static var baseURL: URL {
        if let string = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: string) {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }
}
