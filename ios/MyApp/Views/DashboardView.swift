import SwiftUI

struct DashboardView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }

            WeeklyScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }

            TaskListView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
        }
    }
}

#Preview {
    DashboardView()
        .environment(AuthenticationService())
        .environment(TaskService())
        .environment(PlannerService())
        .environment(NotificationService.shared)
        .environment(CalendarService())
        .environment(ScheduleService())
}
