import SwiftData
import SwiftUI

@main
struct MyAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var authService = AuthenticationService()
    @State private var localStore: LocalStore
    @State private var connectivity: ConnectivityMonitor
    @State private var syncManager: SyncManager
    @State private var taskService: TaskService
    @State private var plannerService = PlannerService()
    @State private var calendarService: CalendarService
    @State private var scheduleService: ScheduleService
    @State private var recommendationService: RecommendationService
    @State private var categoryStore = CategoryStore()
    @State private var appearance = AppearanceSettings()
    @State private var habitService = HabitService()

    init() {
        let store = LocalStore()
        let connectivity = ConnectivityMonitor()
        let syncManager = SyncManager(store: store, connectivity: connectivity)
        let calendarService = CalendarService()

        _authService = State(
            initialValue: AuthenticationService(localStore: store)
        )
        _localStore = State(initialValue: store)
        _connectivity = State(initialValue: connectivity)
        _syncManager = State(initialValue: syncManager)
        _calendarService = State(initialValue: calendarService)
        _recommendationService = State(
            initialValue: RecommendationService(calendarService: calendarService)
        )
        _scheduleService = State(
            initialValue: ScheduleService(
                store: store,
                connectivity: connectivity
            )
        )
        _taskService = State(
            initialValue: TaskService(store: store, connectivity: connectivity)
        )
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
                .environment(recommendationService)
                .environment(syncManager)
                .environment(connectivity)
                .environment(categoryStore)
                .environment(appearance)
                .environment(habitService)
                .preferredColorScheme(appearance.theme.colorScheme)
                .task {
                    await authService.restoreSession()
                }
        }
        .modelContainer(localStore.container)
    }
}
