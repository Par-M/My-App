import SwiftUI

struct ContentView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(NotificationService.self) private var notificationService
    @Environment(SyncManager.self) private var syncManager
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(TaskService.self) private var taskService
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(FocusService.self) private var focusService

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
                if !taskService.tasks.isEmpty {
                    await focusService.loadMorningMessage()
                    rescheduleNotifications()
                }
            }
        }
        .task(id: connectivity.isConnected) {
            if connectivity.isConnected, authService.state == .signedIn, syncManager.pendingCount > 0 {
                await syncManager.syncNow()
            }
        }
    }

    private func rescheduleNotifications() {
        let workStart = scheduleService.preference?.workHoursStart ?? 9
        let workEnd = scheduleService.preference?.workHoursEnd ?? 17
        let hasReflectionToday = focusService.reflections.contains {
            Calendar.current.isDateInToday($0.date)
        }
        notificationService.scheduleAll(
            tasks: taskService.tasks,
            events: [],
            blocks: [],
            workHoursStart: workStart,
            workHoursEnd: workEnd,
            hasReflectionToday: hasReflectionToday,
            hasOngoingFocus: false,
            morningMessage: focusService.morningMessage?.message
        )
    }
}

#Preview {
    ContentView()
        .environment(AuthenticationService())
}
