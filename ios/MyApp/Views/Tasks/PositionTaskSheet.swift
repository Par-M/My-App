import SwiftUI

struct PositionTaskSheet: View {
    let taskTitle: String
    let existingTasks: [TaskItem]
    let onPositioned: (TaskItem, Bool) -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var beforeTask: TaskItem?
    @State private var afterTask: TaskItem?

    private var activeTasks: [TaskItem] {
        existingTasks
            .filter { $0.status != .completed }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    private var canPlace: Bool {
        beforeTask != nil || afterTask != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Position \"\(taskTitle)\"")
                            .font(.headline)
                        Text("Choose a task this one should come before or after.")
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
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Before:")
                                .font(.headline)
                            Spacer()
                        }
                        ForEach(activeTasks) { task in
                            taskButton(task, isSelected: beforeTask?.id == task.id) {
                                if beforeTask?.id == task.id {
                                    beforeTask = nil
                                } else {
                                    beforeTask = task
                                    afterTask = nil
                                }
                            }
                        }
                    }

                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                            Text("After:")
                                .font(.headline)
                            Spacer()
                        }
                        ForEach(activeTasks) { task in
                            taskButton(task, isSelected: afterTask?.id == task.id) {
                                if afterTask?.id == task.id {
                                    afterTask = nil
                                } else {
                                    afterTask = task
                                    beforeTask = nil
                                }
                            }
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
                        if let selected = beforeTask {
                            onPositioned(selected, true)
                        } else if let selected = afterTask {
                            onPositioned(selected, false)
                        }
                        dismiss()
                    }
                    .disabled(!canPlace)
                }
            }
        }
    }

    private func taskButton(_ task: TaskItem, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                    if let deadline = task.deadline {
                        Text("Due \(deadline.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
