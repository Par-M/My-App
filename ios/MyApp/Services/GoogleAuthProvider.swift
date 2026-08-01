import Foundation
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum AuthProviderError: Error {
    case missingClientID
    case missingIDToken
    case noPresenter
}

struct GoogleAuthProvider {
    private var clientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    func idToken() async throws -> String {
        #if canImport(GoogleSignIn)
        guard let clientID else {
            throw AuthProviderError.missingClientID
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = Self.rootViewController else {
            throw AuthProviderError.noPresenter
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthProviderError.missingIDToken
        }

        return idToken
        #else
        throw AuthProviderError.missingClientID
        #endif
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
            .first?
            .rootViewController
    }
}
