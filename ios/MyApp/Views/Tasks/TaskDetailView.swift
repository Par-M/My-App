import SwiftUI

struct TaskDetailView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem
    @State private var currentTask: TaskItem
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    init(task: TaskItem) {
        self.task = task
        _currentTask = State(initialValue: task)
    }

    var body: some View {
        List {
            Section {
                Text(currentTask.title)
                    .font(.title2.bold())
                if let description = currentTask.description, !description.isEmpty {
                    Text(description)
                        .foregroundStyle(.secondary)
                }
            }

            if !currentTask.isArchived && currentTask.completedAt == nil {
                Section("Progress") {
                    HStack {
                        Text("\(currentTask.progressPercent)%")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Text("Completed blocks")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(currentTask.progressPercent), total: 100)
                }
            }

            Section("Details") {
                LabeledContent("Status", value: currentTask.status.label)
                LabeledContent("Priority", value: currentTask.priority.label)
                if let deadline = currentTask.deadline {
                    LabeledContent(
                        "Deadline",
                        value: deadline.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if let duration = currentTask.estimatedDuration {
                    LabeledContent("Duration", value: "\(duration) min")
                }
                if let category = currentTask.category, !category.isEmpty {
                    LabeledContent("Category", value: category)
                }
            }

            if let notes = currentTask.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(currentTask.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Edit") {
                    showEdit = true
                }
                .accessibilityIdentifier("editTaskButton")

                Menu {
                    Button(currentTask.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                        toggleArchive()
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("moreMenuButton")
            }
        }
        .sheet(isPresented: $showEdit) {
            TaskFormView(mode: .edit(currentTask)) { saved in
                currentTask = saved
            }
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteTask()
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggleArchive() {
        Task {
            do {
                if currentTask.isArchived {
                    _ = try await taskService.restoreTask(currentTask)
                } else {
                    _ = try await taskService.archiveTask(currentTask)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteTask() {
        Task {
            do {
                try await taskService.deleteTask(currentTask)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
