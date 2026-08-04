import SwiftUI

struct TaskFormView: View {
    enum Mode {
        case add
        case edit(TaskItem)
    }

    @Environment(TaskService.self) private var taskService
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onSaved: ((TaskItem) -> Void)?

    @State private var title: String
    @State private var detail: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var priority: TaskPriority
    @State private var status: TaskStatus
    @State private var hasDuration: Bool
    @State private var durationMinutes: Int
    @State private var category: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, onSaved: ((TaskItem) -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _detail = State(initialValue: "")
            _hasDeadline = State(initialValue: false)
            _deadline = State(initialValue: Date())
            _priority = State(initialValue: .medium)
            _status = State(initialValue: .pending)
            _hasDuration = State(initialValue: false)
            _durationMinutes = State(initialValue: 30)
            _category = State(initialValue: "")
            _notes = State(initialValue: "")
        case .edit(let task):
            _title = State(initialValue: task.title)
            _detail = State(initialValue: task.description ?? "")
            _hasDeadline = State(initialValue: task.deadline != nil)
            _deadline = State(initialValue: task.deadline ?? Date())
            _priority = State(initialValue: task.priority)
            _status = State(initialValue: task.status)
            _hasDuration = State(initialValue: task.estimatedDuration != nil)
            _durationMinutes = State(initialValue: task.estimatedDuration ?? 30)
            _category = State(initialValue: task.category ?? "")
            _notes = State(initialValue: task.notes ?? "")
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("taskTitleField")
                    TextField("Description", text: $detail, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Toggle("Deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(
                            "Due",
                            selection: $deadline,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Toggle("Estimated Duration", isOn: $hasDuration)
                    if hasDuration {
                        Stepper(
                            value: $durationMinutes,
                            in: 1...525600,
                            step: 5
                        ) {
                            Text("\(durationMinutes) min")
                        }
                    }
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                }

                Section {
                    TextField("Category", text: $category)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if case .add = mode, scheduleService.preference == nil {
                    await scheduleService.loadPreferences()
                }
                applyDefaults()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(saveButtonTitle) {
                            Task { await save() }
                        }
                        .disabled(trimmedTitle.isEmpty)
                        .accessibilityIdentifier("saveTaskButton")
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add: "New Task"
        case .edit: "Edit Task"
        }
    }

    private var saveButtonTitle: String {
        switch mode {
        case .add: "Add"
        case .edit: "Save"
        }
    }

    private func applyDefaults() {
        guard case .add = mode else { return }
        guard let preference = scheduleService.preference else { return }
        if !hasDuration {
            durationMinutes = preference.defaultDurationMinutes
        }
        if trimmedTitle.isEmpty {
            priority = TaskPriority(rawValue: preference.defaultPriority) ?? .medium
        }
    }

    private func save() async {
        guard !trimmedTitle.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let deadlineValue = hasDeadline ? deadline : nil
        let durationValue = hasDuration ? durationMinutes : nil
        let categoryValue = category.isEmpty ? nil : category
        let descriptionValue = detail.isEmpty ? nil : detail
        let notesValue = notes.isEmpty ? nil : notes

        do {
            switch mode {
            case .add:
                let created = try await taskService.createTask(
                    title: trimmedTitle,
                    description: descriptionValue,
                    deadline: deadlineValue,
                    priority: priority,
                    status: status,
                    estimatedDuration: durationValue,
                    category: categoryValue,
                    notes: notesValue
                )
                onSaved?(created)
            case .edit(let task):
                var updated = task
                updated.title = trimmedTitle
                updated.description = descriptionValue
                updated.deadline = deadlineValue
                updated.priority = priority
                updated.status = status
                updated.estimatedDuration = durationValue
                updated.category = categoryValue
                updated.notes = notesValue
                let saved = try await taskService.updateTask(updated)
                onSaved?(saved)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
