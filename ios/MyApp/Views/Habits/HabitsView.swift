import SwiftUI

struct HabitsView: View {
    @Environment(HabitService.self) private var habitService

    @State private var isAdding = false
    @State private var editingHabit: Habit?
    @State private var showingDashboard = false

    var body: some View {
        NavigationStack {
            Group {
                if habitService.habits.isEmpty && !habitService.isLoading {
                    ContentUnavailableView(
                        "No habits yet",
                        systemImage: "checkmark.circle",
                        description: Text("Create a habit to start tracking your streak.")
                    )
                } else {
                    List {
                        ForEach(habitService.habits) { stats in
                            HabitRow(stats: stats) {
                                await log(stats)
                            }
                            .onTapGesture {
                                editingHabit = stats.habit
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await habitService.deleteHabit(id: stats.habit.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .refreshable {
                        await habitService.loadDashboard()
                    }
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingDashboard = true
                    } label: {
                        Label("Dashboard", systemImage: "chart.bar.xaxis")
                    }
                    .disabled(habitService.habits.isEmpty)
                    .accessibilityIdentifier("habitDashboardButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add Habit", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addHabitButton")
                }
            }
            .overlay {
                if habitService.isLoading && habitService.habits.isEmpty {
                    ProgressView()
                }
            }
            .task {
                await habitService.loadDashboard()
            }
        }
        .sheet(isPresented: $isAdding) {
            HabitFormView(mode: .add) { _ in
                isAdding = false
            }
        }
        .sheet(item: $editingHabit) { habit in
            HabitFormView(mode: .edit(habit))
        }
        .sheet(isPresented: $showingDashboard) {
            HabitDashboardView()
        }
    }

    private func log(_ stats: HabitStats) async {
        await habitService.logHabit(id: stats.habit.id, count: 1)
    }
}

private struct HabitRow: View {
    @Environment(HabitService.self) private var habitService

    let stats: HabitStats
    let onLog: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                Task { await onLog() }
            }) {
                Image(systemName: stats.isDoneToday ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(
                        stats.isDoneToday ? Color.green : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(stats.isDoneToday)
            .accessibilityIdentifier("logHabitButton")

            VStack(alignment: .leading, spacing: 2) {
                Text(stats.habit.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(stats.habit.scheduleLabel) · goal \(stats.habit.dailyGoal)x")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if stats.isDoneToday {
                Text("\(stats.today?.completedCount ?? 0)/\(stats.habit.dailyGoal)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }

            if stats.currentStreak > 0 {
                Label("\(stats.currentStreak)", systemImage: "flame.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .contentShape(Rectangle())
    }
}
