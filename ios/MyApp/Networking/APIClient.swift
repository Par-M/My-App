import Foundation

final class APIClient {
    private let baseURL: URL
    private let keychain: KeychainManaging
    private var activeRefresh: Task<AuthSession, Error>?

    init(baseURL: URL = APIConfiguration.baseURL, keychain: KeychainManaging = KeychainManager()) {
        self.baseURL = baseURL
        self.keychain = keychain
    }

    func loginWithGoogle(idToken: String) async throws -> AuthSession {
        try await send(AuthEndpoint.google(idToken: idToken))
    }

    func loginDev() async throws -> AuthSession {
        try await send(AuthEndpoint.dev(name: "Dev User", email: "dev@example.com"))
    }

    func me() async throws -> User {
        try await send(AuthEndpoint.me)
    }

    func logout() async throws {
        _ = try await send(AuthEndpoint.logout) as MessageResponse
    }

    func refreshSession() async throws -> AuthSession {
        if let activeRefresh {
            return try await activeRefresh.value
        }

        let task = Task<AuthSession, Error> { [keychain, baseURL] in
            guard let refreshToken = keychain.refreshToken else {
                throw NetworkError.unauthorized
            }

            let url = baseURL.appending(path: AuthEndpoint.refresh(refreshToken: refreshToken).path)
            var request = URLRequest(url: url)
            request.httpMethod = HTTPMethod.post.rawValue
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NetworkError.unauthorized
            }

            let session = try JSONDecoder().decode(AuthSession.self, from: data)
            keychain.save(session)
            return session
        }

        activeRefresh = task
        defer { activeRefresh = nil }

        return try await task.value
    }

    private func send<T: Decodable>(_ endpoint: Endpoint, didRetry: Bool = false) async throws -> T {
        let urlRequest = try makeRequest(endpoint)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        if http.statusCode == 401, !didRetry, endpoint.requiresAuthentication, keychain.refreshToken != nil {
            _ = try await refreshSession()
            return try await send(endpoint, didRetry: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw NetworkError.unauthorized
            }
            throw NetworkError.httpStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    private func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        let url = baseURL.appending(path: endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if endpoint.requiresAuthentication, let accessToken = keychain.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body = endpoint.body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        return request
    }
}

private struct MessageResponse: Decodable {
    let message: String
}
