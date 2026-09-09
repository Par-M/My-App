import Charts
import SwiftUI

struct HabitDashboardView: View {
    @Environment(HabitService.self) private var habitService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage = habitService.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if habitService.habits.isEmpty {
                        ContentUnavailableView(
                            "No data yet",
                            systemImage: "chart.bar",
                            description: Text("Log a few completions to see your progress.")
                        )
                    } else {
                        summaryHeader

                        section("On track", habits: habitService.habits.filter {
                            $0.completionRate30d >= 0.75
                        }, emptyMessage: "No habits on track yet")

                        section("Needs work", habits: habitService.habits.filter {
                            $0.completionRate30d < 0.75
                        }, emptyMessage: "Nothing to fix — great job!")
                    }
                }
                .padding()
            }
            .navigationTitle("Habit Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summaryHeader: some View {
        let scheduled = habitService.habits.reduce(0) { $0 + $1.scheduled7d }
        let completed = habitService.habits.reduce(0) { $0 + $1.completed7d }
        let rate = scheduled > 0 ? Double(completed) / Double(scheduled) : 1.0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("This week")
                    .font(.headline)
                Spacer()
                Text("\(Int((rate * 100).rounded()))%")
                    .font(.headline)
                    .foregroundStyle(rate >= 0.75 ? .green : .orange)
            }
            ProgressView(value: rate)
                .tint(rate >= 0.75 ? .green : .orange)
            Text("\(completed) of \(scheduled) scheduled completions done")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func section(
        _ title: String,
        habits: [HabitStats],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if habits.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(habits) { stats in
                    HabitCard(stats: stats)
                }
            }
        }
    }
}

private struct HabitCard: View {
    let stats: HabitStats

    private var onTrack: Bool {
        stats.completionRate30d >= 0.75
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.habit.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(stats.habit.scheduleLabel) · goal \(stats.habit.dailyGoal)x/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if stats.currentStreak > 0 {
                    Label("\(stats.currentStreak)", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Chart(stats.last7Days, id: \.self) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Done", day.completedCount)
                )
                .foregroundStyle(barColor(day))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .frame(height: 90)

            HStack {
                Text("30-day rate: \(Int((stats.completionRate30d * 100).rounded()))%")
                    .font(.footnote)
                    .foregroundStyle(onTrack ? .green : .orange)
                Spacer()
                Text("Best streak: \(stats.bestStreak)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func barColor(_ day: HabitDayStats) -> Color {
        guard day.scheduled else { return Color(.systemGray5) }
        if day.completedCount >= stats.habit.dailyGoal {
            return .green
        }
        if day.completedCount > 0 {
            return .orange
        }
        return .red
    }
}
