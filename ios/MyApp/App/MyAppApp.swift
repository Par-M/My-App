import SwiftUI

@main
struct MyAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var authService = AuthenticationService()
    @State private var taskService = TaskService()
    @State private var plannerService = PlannerService()
    @State private var calendarService: CalendarService
    @State private var scheduleService: ScheduleService

    init() {
        let calendarService = CalendarService()
        _calendarService = State(initialValue: calendarService)
        _scheduleService = State(initialValue: ScheduleService(calendarService: calendarService))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(taskService)
                .environment(plannerService)
                .environment(NotificationService.shared)
                .environment(calendarService)
                .environment(scheduleService)
                .task {
                    await authService.restoreSession()
                }
        }
    }
}
