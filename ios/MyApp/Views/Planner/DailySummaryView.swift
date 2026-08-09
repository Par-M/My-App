import SwiftUI

struct DailySummaryView: View {
    @Environment(PlannerService.self) private var planner

    var body: some View {
        Group {
            if let summary = planner.summary {
                List {
                    Section("Overview") {
                        LabeledContent("Date", value: summary.date.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Hours worked", value: formattedHours(summary.hoursWorked))
                        LabeledContent("Tasks remaining", value: "\(summary.tasksRemaining)")
                        LabeledContent("Tasks rescheduled", value: "\(summary.tasksMoved)")
                        LabeledContent(
                            "Schedule adherence",
                            value: summary.scheduleAdherence.formatted(.percent.precision(.fractionLength(0)))
                        )
                        ProgressView(value: min(max(summary.scheduleAdherence, 0), 1))
                            .tint(.accentColor)
                    }

                    if !summary.missedToday.isEmpty {
                        Section("Missed Today") {
                            ForEach(summary.missedToday) { miss in
                                missedRow(miss)
                            }
                        }
                    }

                    Section {
                        NavigationLink("Why did I miss tasks?") {
                            MissedReasonsView()
                        }
                    }

                    if !summary.completed.isEmpty {
                        Section("Completed") {
                            ForEach(summary.completed) { task in
                                summaryRow(task, icon: "checkmark.circle.fill", tint: .green)
                            }
                        }
                    }

                    if !summary.inProgress.isEmpty {
                        Section("In Progress") {
                            ForEach(summary.inProgress) { task in
                                summaryRow(task, icon: "clock.fill", tint: .orange)
                            }
                        }
                    }

                    if !summary.pending.isEmpty {
                        Section("Pending") {
                            ForEach(summary.pending) { task in
                                summaryRow(task, icon: "circle", tint: .secondary)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No summary yet",
                    systemImage: "chart.bar",
                    description: Text("Pull to refresh to see today's progress.")
                )
            }
        }
        .navigationTitle("Daily Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task { await planner.loadSummary() }
        .refreshable { await planner.loadSummary() }
    }

    private func missedRow(_ miss: MissedTaskEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(miss.taskTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let reason = miss.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func summaryRow(_ task: ScheduledTask, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let duration = task.actualDuration ?? task.estimatedDuration {
                    Text("\(duration) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formattedHours(_ hours: Double) -> String {
        if hours < 0.01 { return "0 min" }
        if hours >= 1 {
            return "\(hours.formatted(.number.precision(.fractionLength(1)))) h"
        }
        return "\(Int((hours * 60).rounded())) min"
    }
}

#Preview {
    NavigationStack {
        DailySummaryView()
            .environment(PlannerService())
    }
}
