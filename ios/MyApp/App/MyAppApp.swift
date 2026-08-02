import SwiftUI

@main
struct MyAppApp: App {
    @State private var authService = AuthenticationService()
    @State private var taskService = TaskService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(taskService)
                .task {
                    await authService.restoreSession()
                }
        }
    }
}
