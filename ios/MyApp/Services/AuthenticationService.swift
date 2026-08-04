import Foundation
import Observation

@MainActor
@Observable
final class AuthenticationService {
    enum State {
        case unknown
        case signedOut
        case signedIn
    }

    private(set) var state: State = .unknown
    private(set) var user: User?

    private let apiClient: APIClient
    private let keychain: KeychainManaging
    private let googleProvider: GoogleAuthProvider
    private let localStore: LocalStore?

    init(
        apiClient: APIClient? = nil,
        keychain: KeychainManaging? = nil,
        googleProvider: GoogleAuthProvider? = nil,
        localStore: LocalStore? = nil
    ) {
        self.apiClient = apiClient ?? APIClient()
        self.keychain = keychain ?? KeychainManager()
        self.googleProvider = googleProvider ?? GoogleAuthProvider()
        self.localStore = localStore
    }

    func restoreSession() async {
        guard keychain.loadSession() != nil else {
            state = .signedOut
            return
        }

        do {
            user = try await apiClient.me()
            state = .signedIn
        } catch {
            do {
                let session = try await apiClient.refreshSession()
                apply(session)
            } catch {
                keychain.clear()
                user = nil
                state = .signedOut
            }
        }
    }

    func signInWithGoogle() async throws {
        let idToken = try await googleProvider.idToken()
        let session = try await apiClient.loginWithGoogle(idToken: idToken)
        apply(session)
    }

    func signInDev() async throws {
        let session = try await apiClient.loginDev()
        apply(session)
    }

    func signOut() {
        Task {
            try? await apiClient.logout()
            await NotificationService.shared.unregisterDevice()
            NotificationService.shared.clearLocalState()
        }
        keychain.clear()
        user = nil
        state = .signedOut
        localStore?.clearAll()
    }

    private func apply(_ session: AuthSession) {
        keychain.save(session)
        user = session.user
        state = .signedIn
    }
}
