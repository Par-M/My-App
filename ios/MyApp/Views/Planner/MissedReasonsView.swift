import SwiftUI

struct MissedReasonsView: View {
    @Environment(PlannerService.self) private var planner

    var body: some View {
        Group {
            if let response = planner.missedReasons {
                if response.byCategory.isEmpty {
                    ContentUnavailableView(
                        "No missed tasks",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing missed so far. Great work!")
                    )
                } else {
                    List {
                        ForEach(response.byCategory) { category in
                            Section {
                                ForEach(category.reasons) { miss in
                                    reasonRow(miss)
                                }
                            } header: {
                                HStack {
                                    Text(category.category)
                                    Spacer()
                                    Text("\(category.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if planner.isLoading {
                ProgressView("Loading…")
            } else {
                ContentUnavailableView(
                    "No data",
                    systemImage: "chart.bar",
                    description: Text("Pull to refresh to load your missed-task history.")
                )
            }
        }
        .navigationTitle("Why Did I Miss Tasks?")
        .navigationBarTitleDisplayMode(.inline)
        .task { await planner.loadMissedReasons() }
        .refreshable { await planner.loadMissedReasons() }
    }

    private func reasonRow(_ miss: MissedTaskEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(miss.taskTitle)
                .font(.body.weight(.medium))
            if let reason = miss.reason, !reason.isEmpty {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let missed = miss.missedDeadline {
                    Label(
                        missed.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "calendar.badge.exclamationmark"
                    )
                }
                if let minutes = miss.minutesRemaining {
                    Label("\(minutes) min left", systemImage: "timer")
                }
                if let rescheduledTo = miss.rescheduledTo {
                    Label(
                        "Moved to \(rescheduledTo.formatted(date: .omitted, time: .shortened))",
                        systemImage: "arrow.right"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        MissedReasonsView()
            .environment(PlannerService())
    }
}
