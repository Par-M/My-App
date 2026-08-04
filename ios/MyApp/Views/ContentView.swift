import SwiftUI

struct ContentView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(NotificationService.self) private var notificationService
    @Environment(SyncManager.self) private var syncManager
    @Environment(ConnectivityMonitor.self) private var connectivity

    @State private var onboardingComplete = OnboardingView.isComplete

    var body: some View {
        Group {
            switch authService.state {
            case .unknown:
                ProgressView()
            case .signedOut:
                LoginView()
            case .signedIn:
                if onboardingComplete {
                    DashboardView()
                } else {
                    OnboardingView(onComplete: { onboardingComplete = true })
                }
            }
        }
        .animation(.default, value: authService.state == .signedIn)
        .task(id: authService.state) {
            if authService.state == .signedIn {
                await notificationService.load()
                await syncManager.syncNow()
            }
        }
        .task(id: connectivity.isConnected) {
            if connectivity.isConnected, authService.state == .signedIn, syncManager.pendingCount > 0 {
                await syncManager.syncNow()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthenticationService())
}
