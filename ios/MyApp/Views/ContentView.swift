import SwiftUI

struct ContentView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(NotificationService.self) private var notificationService

    var body: some View {
        Group {
            switch authService.state {
            case .unknown:
                ProgressView()
            case .signedOut:
                LoginView()
            case .signedIn:
                DashboardView()
            }
        }
        .animation(.default, value: authService.state == .signedIn)
        .task(id: authService.state) {
            if authService.state == .signedIn {
                await notificationService.load()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthenticationService())
}
