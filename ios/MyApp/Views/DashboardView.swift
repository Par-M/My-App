import SwiftUI

struct DashboardView: View {
    var body: some View {
        TaskListView()
    }
}

#Preview {
    DashboardView()
        .environment(AuthenticationService())
        .environment(TaskService())
}
