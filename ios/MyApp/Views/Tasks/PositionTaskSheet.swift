import SwiftUI

struct PositionTaskSheet: View {
    let taskTitle: String
    let existingTasks: [TaskItem]
    let onPositioned: (TaskItem, Bool) -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTask: TaskItem?
    @State private var placeBefore = true

    private var activeTasks: [TaskItem] {
        existingTasks
            .filter { $0.status != .completed }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Position \"\(taskTitle)\"")
                            .font(.headline)
                        Text("Should this task come before or after an existing task?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if activeTasks.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No other tasks",
                            systemImage: "list.bullet",
                            description: Text("Add more tasks to position them relative to each other.")
                        )
                    }
                } else {
                    Section("Place relative to") {
                        ForEach(activeTasks) { task in
                            Button {
                                selectedTask = task
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(selectedTask?.id == task.id ? .primary : .primary)
                                        if let deadline = task.deadline {
                                            Text("Due \(deadline.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedTask?.id == task.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedTask != nil {
                        Section("Position") {
                            Picker("Position", selection: $placeBefore) {
                                Text("Before").tag(true)
                                Text("After").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color(.secondarySystemBackground))
                        }
                    }
                }
            }
            .navigationTitle("Position Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Place") {
                        if let selected = selectedTask {
                            onPositioned(selected, placeBefore)
                        }
                        dismiss()
                    }
                    .disabled(selectedTask == nil)
                }
            }
        }
    }
}
