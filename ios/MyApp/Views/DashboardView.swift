import SwiftUI

struct DashboardView: View {
    private enum Tab: Hashable {
        case schedule
        case tasks
        case habits
        case focus
    }

    @State private var selectedTab: Tab = .schedule

    var body: some View {
        TabView(selection: $selectedTab) {
            WeeklyScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(Tab.schedule)

            TaskListView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(Tab.tasks)

            HabitsView()
                .tabItem {
                    Label("Habits", systemImage: "checkmark.circle")
                }
                .tag(Tab.habits)

            FocusDashboardView()
                .tabItem {
                    Label("Focus", systemImage: "timer")
                }
                .tag(Tab.focus)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFocus)) { _ in
            selectedTab = .focus
        }
    }
}