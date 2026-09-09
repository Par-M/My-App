import SwiftUI
import UIKit

struct HabitsView: View {
    @Environment(HabitService.self) private var habitService
    @Environment(TaskService.self) private var taskService

    @State private var isAdding = false
    @State private var editingHabit: Habit?
    @State private var showingDashboard = false
    @State private var habitPendingDelete: Habit?

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
                        if let errorMessage = habitService.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .listRowBackground(Color.orange.opacity(0.08))
                        }
                        ForEach(habitService.habits) { stats in
                            HabitRow(stats: stats) {
                                await log(stats)
                            }
                            .onTapGesture {
                                editingHabit = stats.habit
                            }
                            .accessibilityHint("Double tap to edit")
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    habitPendingDelete = stats.habit
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingHabit = stats.habit
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
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
            .onChange(of: taskService.dataVersion) { _, _ in
                Task { await habitService.loadDashboard() }
            }
        }
        .confirmationDialog(
            habitPendingDelete == nil ? "" : "Delete \(habitPendingDelete!.title)?",
            isPresented: Binding(
                get: { habitPendingDelete != nil },
                set: { if !$0 { habitPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let habit = habitPendingDelete {
                    Task { await habitService.deleteHabit(id: habit.id) }
                }
                habitPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                habitPendingDelete = nil
            }
        } message: {
            Text("This removes the habit and its history. This cannot be undone.")
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct HabitRow: View {
    @Environment(HabitService.self) private var habitService

    let stats: HabitStats
    let onLog: () async -> Void

    @State private var dragValue: Double?

    private var goal: Int { stats.habit.dailyGoal }
    private var completedCount: Int { stats.today?.completedCount ?? 0 }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { dragValue ?? Double(completedCount) },
            set: { dragValue = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if goal > 1 {
                    Text("\(completedCount)/\(goal)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(
                            completedCount >= goal ? Color.green : Color.secondary
                        )
                        .frame(width: 40, alignment: .leading)
                } else {
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
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.habit.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(stats.habit.scheduleLabel) · goal \(goal)x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if goal == 1 && stats.isDoneToday {
                    Text("\(completedCount)/\(goal)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }

                if stats.currentStreak > 0 {
                    Label("\(stats.currentStreak)", systemImage: "flame.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            if goal > 1 {
                HStack(spacing: 10) {
                    Slider(value: sliderValue, in: 0...Double(goal), step: 1) { editing in
                        if !editing {
                            let value = Int(sliderValue.wrappedValue.rounded())
                            dragValue = nil
                            Task { await commit(value) }
                        }
                    }
                    .accessibilityIdentifier("habitCountSlider")
                    Text("\(Int(sliderValue.wrappedValue.rounded()))/\(goal)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func commit(_ value: Int) async {
        await habitService.setHabitDayCount(id: stats.habit.id, count: value)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
