import SwiftUI

struct TodayView: View {
    @Environment(PlannerService.self) private var planner
    @Environment(TaskService.self) private var taskService
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(NotificationService.self) private var notificationService
    @Environment(SyncManager.self) private var syncManager

    @State private var showSummary = false
    @State private var errorDismissed = false
    @State private var showSettings = false
    @State private var reschedulingTask: TaskItem?

    var body: some View {
        NavigationStack {
            Group {
                if let today = planner.today {
                    List {
                        Section {
                            header(today)
                        }

                        if !taskService.overdueTasks.isEmpty {
                            Section("Behind Schedule") {
                                ForEach(taskService.overdueTasks) { task in
                                    overdueRow(task)
                                }
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

                        Section {
                            syncStatusRow()
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await planner.loadToday() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(planner.isLoading)
                }
            }
            .task {
                await planner.loadToday()
                await taskService.loadOverdue()
            }
            .refreshable {
                await planner.loadToday()
                await taskService.loadOverdue()
            }
            .onChange(of: notificationService.lastDeepLink) { _, _ in
                Task {
                    await planner.loadToday()
                    await taskService.loadOverdue()
                }
            }
            .sheet(item: $reschedulingTask) { task in
                RescheduleSheet(task: task) { minutes, reason in
                    Task { await reschedule(task, minutes: minutes, reason: reason) }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
        VStack(spacing: 14) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month())
                .font(.subheadline)
                .foregroundStyle(.secondary)

            workEndCountdown(today)

            HStack(spacing: 12) {
                statPill(
                    value: "\(today.completedToday)",
                    label: "Done",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
                statPill(
                    value: "\(today.tasksRemaining)",
                    label: "Left",
                    systemImage: "clock.arrow.circlepath",
                    tint: .orange
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func workEndCountdown(_ today: TodayResponse) -> some View {
        let workEnd = workEndDate()
        let totalWorkMinutes = max(1, workTotalMinutes())

        return TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let minsLeft = max(0, Int(workEnd.timeIntervalSince(now) / 60))
            let hours = minsLeft / 60
            let mins = minsLeft % 60
            let color = minutesLeftColor(minsLeft, total: totalWorkMinutes)
            let progress = min(1.0, Double(totalWorkMinutes - minsLeft) / Double(totalWorkMinutes))

            ZStack {
                Circle()
                    .stroke(.quinary, lineWidth: 14)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                VStack(spacing: 3) {
                    if minsLeft <= 0 {
                        Image(systemName: "checkmark")
                            .font(.title2.bold())
                            .foregroundStyle(.green)
                        Text("Done")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    } else {
                        Text("\(hours > 0 ? "\(hours)h " : "")\(mins)m")
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(color)
                        Text("left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 100, height: 100)
        }
    }

    private func workEndDate() -> Date {
        let cal = Calendar.current
        let now = Date()
        let hour = scheduleService.preference?.workHoursEnd ?? 17
        let endHour = min(max(Int(hour), 0), 23)
        var components = cal.dateComponents([.year, .month, .day], from: now)
        components.hour = endHour
        components.minute = 0
        return cal.date(from: components) ?? now
    }

    private func workTotalMinutes() -> Int {
        let cal = Calendar.current
        let now = Date()
        let startHour = scheduleService.preference?.workHoursStart ?? 9
        let endHour = scheduleService.preference?.workHoursEnd ?? 17
        let startComp = cal.dateComponents([.year, .month, .day], from: now)
        var s = startComp
        s.hour = Int(startHour)
        s.minute = 0
        var e = startComp
        e.hour = min(max(Int(endHour), 0), 23)
        e.minute = 0
        guard let startDate = cal.date(from: s), let endDate = cal.date(from: e) else { return 480 }
        return max(1, Int(endDate.timeIntervalSince(startDate) / 60))
    }

    private func minutesLeftColor(_ remaining: Int, total: Int) -> Color {
        let ratio = Double(remaining) / Double(max(total, 1))
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .orange }
        return .red
    }

    private func statPill(value: String, label: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.bold())
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.quinary, in: Capsule())
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

    private func syncStatusRow() -> some View {
        HStack(spacing: 12) {
            if syncManager.isSyncing {
                ProgressView()
            } else if syncManager.pendingCount > 0 {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let lastSync = syncManager.lastSyncDate {
                    Text("Last synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if syncManager.pendingCount > 0 {
                    Text("\(syncManager.pendingCount) change(s) waiting to sync")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let error = syncManager.lastSyncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("Sync Now") {
                Task { await syncManager.syncNow() }
            }
            .font(.caption.weight(.semibold))
            .disabled(syncManager.isSyncing)
        }
    }

    private func overdueRow(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
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
                reschedulingTask = task
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 2)
    }

    private func reschedule(_ task: TaskItem, minutes: Int, reason: String?) async {
        do {
            _ = try await taskService.rescheduleTask(task, minutesRemaining: minutes, reason: reason)
            await planner.loadToday()
            await scheduleService.loadBlocks()
            await taskService.loadOverdue()
        } catch {
            planner.presentError(error.localizedDescription)
        }
    }

}

private extension TodayResponse {
    var tasksRemainingForSummary: Int {
        nextTasks.count
    }

    var tasksRemaining: Int {
        (currentTask != nil ? 1 : 0) + nextTasks.count
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
