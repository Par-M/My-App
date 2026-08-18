import SwiftUI

struct RescheduleSheet: View {
    let task: TaskItem
    let onSubmit: (Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var reason: String = ""

    private static let suggestedReasons = [
        "Took longer than planned",
        "Got distracted",
        "Overlapping meetings",
        "Lost track of time",
        "Task was too big",
    ]

    init(task: TaskItem, onSubmit: @escaping (Int, String?) -> Void) {
        self.task = task
        self.onSubmit = onSubmit
        let duration = task.estimatedDuration ?? 30
        _minutes = State(initialValue: min(max(duration, 5), 180))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    LabeledContent("Title", value: task.title)
                    if let deadline = task.deadline {
                        LabeledContent(
                            "Deadline",
                            value: deadline.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                Section("How much time remains?") {
                    Picker("Minutes", selection: $minutes) {
                        ForEach(Array(stride(from: 5, through: 180, by: 5)), id: \.self) { value in
                            Text("\(value) min").tag(value)
                        }
                    }
                }

                Section("Why was it missed? (optional)") {
                    TextField("Reason", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.suggestedReasons, id: \.self) { suggestion in
                                Button(suggestion) {
                                    reason = suggestion
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What happens next")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Your unfinished calendar blocks for this task will move into the next \(minutes) minutes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Reschedule Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reschedule") {
                        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSubmit(minutes, trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
