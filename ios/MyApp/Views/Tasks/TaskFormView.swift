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
    @State private var durationHours: Int
    @State private var durationMinutesPart: Int
    @State private var hasRepeat: Bool
    @State private var repeatDays: Set<Int>
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
            _deadline = State(initialValue: Self.roundedToQuarterHour(Date()))
            _priority = State(initialValue: .medium)
            _status = State(initialValue: .pending)
            _hasDuration = State(initialValue: false)
            _durationHours = State(initialValue: 0)
            _durationMinutesPart = State(initialValue: 30)
            _hasRepeat = State(initialValue: false)
            _repeatDays = State(initialValue: [])
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
            let minutes = task.estimatedDuration ?? 30
            _durationHours = State(initialValue: minutes / 60)
            _durationMinutesPart = State(initialValue: minutes % 60)
            _hasRepeat = State(initialValue: task.repeatWeekdays?.isEmpty == false)
            _repeatDays = State(initialValue: Set(task.repeatWeekdays ?? []))
            _category = State(initialValue: task.category ?? "")
            _notes = State(initialValue: task.notes ?? "")
        }
    }

    private static func roundedToQuarterHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        return calendar.date(
            bySettingHour: calendar.component(.hour, from: date),
            minute: minute - (minute % 15),
            second: 0,
            of: date
        ) ?? date
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var deadlineHour: Int {
        Calendar.current.component(.hour, from: deadline)
    }

    private var deadlineMinute: Int {
        Calendar.current.component(.minute, from: deadline)
    }

    private var hourBinding: Binding<Double> {
        Binding(
            get: { Double(deadlineHour) },
            set: { newValue in
                deadline = Calendar.current.date(
                    bySettingHour: Int(newValue),
                    minute: deadlineMinute,
                    second: 0,
                    of: deadline
                ) ?? deadline
            }
        )
    }

    private var minuteBinding: Binding<Double> {
        Binding(
            get: { Double(deadlineMinute) },
            set: { newValue in
                deadline = Calendar.current.date(
                    bySettingHour: deadlineHour,
                    minute: Int(newValue),
                    second: 0,
                    of: deadline
                ) ?? deadline
            }
        )
    }

    private var totalDurationMinutes: Int {
        durationHours * 60 + durationMinutesPart
    }

    private var totalDurationLabel: String {
        if totalDurationMinutes < 60 {
            return "= \(totalDurationMinutes) min"
        }
        return "= \(totalDurationMinutes / 60)h \(totalDurationMinutes % 60)m"
    }

    private static let weekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    private var selectedWeekdaysValue: [Int]? {
        hasRepeat ? Array(repeatDays).sorted() : nil
    }

    private func repeatDayButton(_ day: Int) -> some View {
        let isSelected = repeatDays.contains(day)
        return Button {
            if isSelected {
                repeatDays.remove(day)
            } else {
                repeatDays.insert(day)
            }
        } label: {
            Text(Self.weekdayLetters[day])
                .font(.subheadline.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(
                    isSelected ? Color.accentColor : Color(.secondarySystemBackground),
                    in: Circle()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("repeatDay\(day)")
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
                            "Date",
                            selection: $deadline,
                            displayedComponents: .date
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Slider(value: hourBinding, in: 0...23, step: 1)
                                    Text("Hour: \(deadlineHour)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Slider(value: minuteBinding, in: 0...45, step: 15)
                                    Text("Minute: \(String(format: "%02d", deadlineMinute))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Toggle("Estimated Duration", isOn: $hasDuration)
                    if hasDuration {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hours")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("0", value: $durationHours, format: .number)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                            }
                            Text("h")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Minutes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("0", value: $durationMinutesPart, format: .number)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                            }
                            Text("m")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(totalDurationLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Repeats", isOn: $hasRepeat)
                    if hasRepeat {
                        HStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { day in
                                repeatDayButton(day)
                            }
                        }
                        .frame(maxWidth: .infinity)
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
            durationHours = preference.defaultDurationMinutes / 60
            durationMinutesPart = preference.defaultDurationMinutes % 60
        }
        if trimmedTitle.isEmpty {
            priority = TaskPriority(rawValue: preference.defaultPriority) ?? .medium
        }
    }

    private func save() async {
        guard !trimmedTitle.isEmpty else { return }
        guard !hasDuration || totalDurationMinutes >= 1 else {
            errorMessage = "Estimated duration must be at least 1 minute."
            return
        }
        isSaving = true
        defer { isSaving = false }

        let deadlineValue = hasDeadline ? deadline : nil
        let durationValue = hasDuration ? totalDurationMinutes : nil
        let categoryValue = category.isEmpty ? nil : category
        let descriptionValue = detail.isEmpty ? nil : detail
        let notesValue = notes.isEmpty ? nil : notes
        let repeatWeekdaysValue = hasRepeat ? selectedWeekdaysValue : nil

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
                    notes: notesValue,
                    repeatWeekdays: repeatWeekdaysValue
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
                updated.repeatWeekdays = repeatWeekdaysValue
                let saved = try await taskService.updateTask(updated)
                onSaved?(saved)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
