import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    var onChangeStatus: (TaskStatus) -> Void = { _ in }

    private var statusColor: Color {
        switch task.status {
        case .pending: .gray
        case .inProgress: .blue
        case .completed: .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                PriorityBadge(priority: task.priority)
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.status == .completed, color: .secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                if let deadline = task.deadline {
                    Label(
                        deadline.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "calendar"
                    )
                }
                if let category = task.category, !category.isEmpty {
                    Text(category)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 8)
                statusMenu
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    onChangeStatus(status)
                } label: {
                    if status == task.status {
                        Label(status.label, systemImage: "checkmark")
                    } else {
                        Text(status.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(task.status.label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9).weight(.semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
            .fixedSize()
        }
    }
}

struct DeferredTaskRow: View {
    let task: TaskItem
    var onChangeStatus: (TaskStatus) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    PriorityBadge(priority: task.priority)
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    if let deadline = task.deadline {
                        Label(
                            "Missed \(deadline.formatted(date: .abbreviated, time: .shortened))",
                            systemImage: "calendar.badge.exclamationmark"
                        )
                    } else if let start = task.startAt {
                        Label(
                            "Was scheduled \(start.formatted(date: .omitted, time: .shortened))",
                            systemImage: "clock.badge.exclamationmark"
                        )
                    } else {
                        Text("Behind schedule")
                    }
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(TaskStatus.allCases) { status in
                            Button {
                                onChangeStatus(status)
                            } label: {
                                if status == task.status {
                                    Label(status.label, systemImage: "checkmark")
                                } else {
                                    Text(status.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(task.status.label)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9).weight(.semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                        .fixedSize()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    private var color: Color {
        switch priority {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }

    var body: some View {
        Image(systemName: "flag.fill")
            .font(.caption)
            .foregroundStyle(color)
            .accessibilityLabel("\(priority.label) priority")
    }
}

struct TaskListView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(AuthenticationService.self) private var authService
    @Environment(NotificationService.self) private var notificationService

    @State private var searchText = ""
    @State private var priorityFilter: TaskPriority?
    @State private var statusFilter: TaskStatus?
    @State private var sortOption: TaskService.SortOption = .created
    @State private var sortAscending = false
    @State private var showAddTask = false
    @State private var showNotificationSettings = false
    @State private var showSettings = false
    @State private var showOverdue = false
    @State private var reschedulingTask: TaskItem?
    @State private var errorDismissed = false
    @State private var isCompletedExpanded = false
    @State private var confirmSignOut = false

    private struct LoadKey: Hashable {
        let search: String
        let priority: TaskPriority?
        let status: TaskStatus?
        let archived: Bool
        let sort: TaskService.SortOption
        let order: String
        let dataVersion: Int
    }

    private var loadKey: LoadKey {
        LoadKey(
            search: searchText,
            priority: priorityFilter,
            status: statusFilter,
            archived: taskService.showingArchived,
            sort: sortOption,
            order: sortAscending ? "asc" : "desc",
            dataVersion: taskService.dataVersion
        )
    }

    private var activeTasks: [TaskItem] {
        taskService.tasks.filter { $0.status != .completed }
    }

    private var completedTasks: [TaskItem] {
        taskService.tasks.filter { $0.status == .completed }
    }

    private var deferredTasks: [TaskItem] {
        let deferredIDs = Set(taskService.overdueTasks.map(\.id))
        return activeTasks.filter { deferredIDs.contains($0.id) }
    }

    private var schedulableTasks: [TaskItem] {
        let deferredIDs = Set(taskService.overdueTasks.map(\.id))
        return activeTasks.filter { !deferredIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if taskService.isLoading && taskService.tasks.isEmpty {
                    ProgressView("Loading tasks…")
                } else if taskService.tasks.isEmpty {
                    if !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ContentUnavailableView(
                            taskService.showingArchived ? "No Archived Tasks" : "No Tasks Yet",
                            systemImage: "checklist",
                            description: Text(
                                taskService.showingArchived
                                    ? "Tasks you archive will appear here."
                                    : "Tap + to create your first task."
                            )
                        )
                    }
                } else {
                    List {
                        if !deferredTasks.isEmpty && !taskService.showingArchived && statusFilter == nil {
                            Section {
                                ForEach(deferredTasks) { task in
                                    NavigationLink(value: task) {
                                        DeferredTaskRow(task: task) { status in
                                            Task {
                                                try? await taskService.setStatus(status, for: task)
                                            }
                                        }
                                    }
                                }
                            } header: {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Behind Schedule")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }

                        ForEach(schedulableTasks) { task in
                            NavigationLink(value: task) {
                                TaskRow(task: task) { status in
                                    Task {
                                        try? await taskService.setStatus(status, for: task)
                                    }
                                }
                            }
                        }

                        if !completedTasks.isEmpty && statusFilter == nil {
                            Section {
                                DisclosureGroup(isExpanded: $isCompletedExpanded) {
                                    ForEach(completedTasks) { task in
                                        NavigationLink(value: task) {
                                            TaskRow(task: task) { status in
                                                Task {
                                                    try? await taskService.setStatus(status, for: task)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text("Completed")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(completedTasks.count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search tasks")
                }
            }
            .navigationTitle(taskService.showingArchived ? "Archived" : "Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let name = authService.user?.name {
                            Text(name)
                        }
                        if let email = authService.user?.email {
                            Text(email)
                        }
                        Divider()
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Button {
                            showNotificationSettings = true
                        } label: {
                            Label("Notifications", systemImage: "bell")
                        }
                        Button("Log Out", role: .destructive) {
                            confirmSignOut = true
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .accessibilityLabel("Account")
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    if !taskService.overdueTasks.isEmpty {
                        Button {
                            showOverdue = true
                        } label: {
                            Label("Overdue", systemImage: "exclamationmark.triangle")
                                .badge(taskService.overdueTasks.count)
                        }
                        .accessibilityIdentifier("overdueBadgeButton")
                    }

                    Button {
                        showAddTask = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addTaskButton")

                    Menu {
                        ForEach(TaskService.SortOption.allCases) { option in
                            Button {
                                if sortOption == option {
                                    sortAscending.toggle()
                                } else {
                                    sortOption = option
                                    sortAscending = option != .deadline
                                }
                            } label: {
                                if sortOption == option {
                                    Label(
                                        option.label,
                                        systemImage: sortAscending ? "arrow.up" : "arrow.down"
                                    )
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }

                    Menu {
                        Menu("Priority") {
                            Button("All") { priorityFilter = nil }
                            ForEach(TaskPriority.allCases) { priority in
                                Button(priority.label) { priorityFilter = priority }
                            }
                        }
                        Menu("Status") {
                            Button("All") { statusFilter = nil }
                            ForEach(TaskStatus.allCases) { status in
                                Button(status.label) { statusFilter = status }
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("filterMenuButton")

                    Button {
                        taskService.setShowingArchived(!taskService.showingArchived)
                    } label: {
                        Label(
                            taskService.showingArchived ? "Active" : "Archived",
                            systemImage: "archivebox"
                        )
                    }
                    .accessibilityIdentifier("archiveToggleButton")
                }
            }
            .navigationDestination(for: TaskItem.self) { task in
                TaskDetailView(task: task)
            }
            .sheet(isPresented: $showAddTask) {
                TaskFormView(mode: .add)
            }
            .sheet(isPresented: $showNotificationSettings) {
                NavigationStack {
                    NotificationSettingsView()
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showOverdue) {
                OverdueListSheet { task in
                    showOverdue = false
                    reschedulingTask = task
                }
            }
            .sheet(item: $reschedulingTask) { task in
                RescheduleSheet(task: task) { minutes, reason in
                    Task { await reschedule(task, minutes: minutes, reason: reason) }
                }
            }
            .confirmationDialog(
                "Log out?",
                isPresented: $confirmSignOut,
                titleVisibility: .visible
            ) {
                Button("Log Out", role: .destructive) {
                    authService.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can sign back in anytime. Your data is synced to your account.")
            }
            .task(id: loadKey) {
                await taskService.loadTasks(
                    search: searchText,
                    priority: priorityFilter,
                    status: statusFilter,
                    sort: sortOption,
                    order: sortAscending ? "asc" : "desc"
                )
            }
            .task {
                await taskService.loadOverdue()
            }
            .onChange(of: taskService.tasks) { _, tasks in
                notificationService.scheduleLocalNotifications(tasks: tasks)
            }
            .overlay(alignment: .bottom) {
                if let errorMessage = taskService.errorMessage, !errorDismissed {
                    VStack {
                        HStack {
                            Text(errorMessage)
                                .font(.footnote)
                            Spacer()
                            Button {
                                errorDismissed = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                    }
                }
            }
        }
    }

    private func reschedule(_ task: TaskItem, minutes: Int, reason: String?) async {
        do {
            _ = try await taskService.rescheduleTask(task, minutesRemaining: minutes, reason: reason)
            await taskService.loadOverdue()
        } catch {
            taskService.presentError(error.localizedDescription)
        }
    }
}

private struct OverdueListSheet: View {
    @Environment(TaskService.self) private var taskService
    @Environment(\.dismiss) private var dismiss
    let onReschedule: (TaskItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                if taskService.overdueTasks.isEmpty {
                    ContentUnavailableView(
                        "No overdue tasks",
                        systemImage: "checkmark.circle",
                        description: Text("You're all caught up.")
                    )
                } else {
                    ForEach(taskService.overdueTasks) { task in
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.body.weight(.medium))
                                if let deadline = task.deadline {
                                    Text("Missed \(deadline.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let start = task.startAt {
                                    Text("Was scheduled at \(start.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Behind schedule")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Reschedule") {
                                onReschedule(task)
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle("Overdue Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    TaskListView()
        .environment(TaskService())
        .environment(AuthenticationService())
        .environment(NotificationService.shared)
}
