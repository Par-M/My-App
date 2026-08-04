import SwiftUI

struct DashboardView: View {
    var body: some View {
        TabView {
            TaskListView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }

            WeeklyScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
        }
    }
}

#Preview {
    DashboardView()
        .environment(AuthenticationService())
        .environment(TaskService())
        .environment(CalendarService())
        .environment(ScheduleService())
}
