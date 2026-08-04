import SwiftUI

struct TodayView: View {
    @Environment(PlannerService.self) private var planner
    @Environment(TaskService.self) private var taskService
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(NotificationService.self) private var notificationService

    @State private var activeFocusTask: ScheduledTask?
    @State private var showSummary = false
    @State private var errorDismissed = false

    var body: some View {
        NavigationStack {
            Group {
                if let today = planner.today {
                    List {
                        Section {
                            header(today)
                        }

                        if let current = today.currentTask {
                            Section("Now Working") {
                                currentTaskRow(current)
                            }
                        }

                        if let priority = today.priorityTask {
                            Section("Today's Priority") {
                                priorityRow(priority)
                            }
                        }

                        if !today.nextTasks.isEmpty {
                            Section("Up Next") {
                                ForEach(today.nextTasks) { task in
                                    nextTaskRow(task)
                                }
                            }
                        }

                        Section {
                            summaryButton(today)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No plan for today",
                        systemImage: "calendar.badge.clock",
                        description: Text("Pull to refresh to build today's plan.")
                    )
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await planner.loadToday() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(planner.isLoading)
                }
            }
            .task { await planner.loadToday() }
            .refreshable { await planner.loadToday() }
            .onChange(of: notificationService.lastDeepLink) { _, _ in
                Task { await planner.loadToday() }
            }
            .sheet(item: $activeFocusTask) { task in
                FocusView(task: task)
            }
            .navigationDestination(isPresented: $showSummary) {
                DailySummaryView()
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { planner.errorMessage != nil && !errorDismissed },
                    set: { if !$0 { errorDismissed = true } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(planner.errorMessage ?? "")
            }
        }
    }

    private func header(_ today: TodayResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(greeting(for: Date.now))
                    .font(.title2.weight(.semibold))
            }

            HStack(spacing: 12) {
                statCard(
                    value: "\(today.completedToday)",
                    label: "Completed",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
                statCard(
                    value: "\(today.focusTimeRemaining) min",
                    label: "Focus left",
                    systemImage: "timer",
                    tint: .orange
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Day progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(today.dayProgress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(max(today.dayProgress, 0), 1))
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private func statCard(value: String, label: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func currentTaskRow(_ task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(task.title)
                    .font(.headline)
                Spacer()
                if let start = task.start {
                    Text(start, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let end = task.end {
                Text("Scheduled until \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                activeFocusTask = task
            } label: {
                Label("Start Focus", systemImage: "play.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private func priorityRow(_ task: ScheduledTask) -> some View {
        HStack(spacing: 12) {
            PriorityBadge(priority: task.priority)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.medium))
                if let category = task.category, !category.isEmpty {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func nextTaskRow(_ task: ScheduledTask) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                if let start = task.start {
                    Text("Starts \(start.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Snooze 30") {
                snooze(task)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func summaryButton(_ today: TodayResponse) -> some View {
        Button {
            showSummary = true
        } label: {
            HStack {
                Label("View Daily Summary", systemImage: "chart.bar")
                    .font(.body.weight(.medium))
                Spacer()
                if today.tasksRemainingForSummary > 0 {
                    Text("\(today.tasksRemainingForSummary) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snooze(_ task: ScheduledTask) {
        Task {
            do {
                if let item = taskService.tasks.first(where: { $0.id == task.id }) {
                    _ = try await taskService.snoozeTask(item, minutes: 30)
                }
                await planner.loadToday()
                await scheduleService.loadBlocks()
            } catch {
                planner.presentError(error.localizedDescription)
            }
        }
    }

    private func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Good night"
        }
    }
}

private extension TodayResponse {
    var tasksRemainingForSummary: Int {
        nextTasks.count
    }
}

#Preview {
    TodayView()
        .environment(PlannerService())
        .environment(TaskService())
        .environment(ScheduleService())
        .environment(CalendarService())
        .environment(NotificationService.shared)
}
