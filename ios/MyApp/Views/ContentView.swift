import SwiftUI

struct ContentView: View {
    @Environment(AuthenticationService.self) private var authService

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
    }
}

#Preview {
    ContentView()
        .environment(AuthenticationService())
}
