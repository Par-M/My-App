import SwiftUI

@main
struct MyAppApp: App {
    @State private var authService = AuthenticationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .task {
                    await authService.restoreSession()
                }
        }
    }
}
