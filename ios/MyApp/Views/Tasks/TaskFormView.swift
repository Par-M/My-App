import SwiftUI

struct TaskFormView: View {
    enum Mode {
        case add
        case edit(TaskItem)
    }

    @Environment(TaskService.self) private var taskService
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(CategoryStore.self) private var categoryStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onSaved: ((TaskItem) -> Void)?

    @State private var title: String
    @State private var detail: String
    @State private var hasFixedEvent: Bool
    @State private var fixedStart: Date
    @State private var fixedEnd: Date
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
    @State private var showPositionSheet = false
    @State private var createdTask: TaskItem?

    init(mode: Mode, onSaved: ((TaskItem) -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _detail = State(initialValue: "")
            _hasFixedEvent = State(initialValue: false)
            let defaultStart = Self.roundedToQuarterHour(Date())
            _fixedStart = State(initialValue: defaultStart)
            _fixedEnd = State(initialValue: defaultStart.addingTimeInterval(30 * 60))
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
            _hasFixedEvent = State(initialValue: task.startAt != nil)
            let start = task.startAt ?? Self.roundedToQuarterHour(Date())
            _fixedStart = State(initialValue: start)
            _fixedEnd = State(
                initialValue: task.endAt ?? start.addingTimeInterval(30 * 60)
            )
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

    private var fixedStartBinding: Binding<Date> {
        Binding(
            get: { fixedStart },
            set: { newValue in
                let calendar = Calendar.current
                var endDate = fixedEnd
                if !calendar.isDate(fixedEnd, inSameDayAs: newValue) {
                    let time = calendar.dateComponents([.hour, .minute], from: fixedEnd)
                    endDate = calendar.date(
                        bySettingHour: time.hour ?? 0,
                        minute: time.minute ?? 0,
                        second: 0,
                        of: newValue
                    ) ?? newValue
                }
                fixedStart = newValue
                if endDate <= newValue {
                    endDate = newValue.addingTimeInterval(30 * 60)
                }
                fixedEnd = endDate
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

    private var categorySuggestions: [String] {
        guard !category.isEmpty else { return [] }
        return Array(
            categoryStore.categories(from: taskService.tasks)
                .filter { $0.localizedCaseInsensitiveContains(category) && $0 != category }
                .prefix(5)
        )
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
                    Toggle("Fixed Event", isOn: $hasFixedEvent)
                    if hasFixedEvent {
                        DatePicker(
                            "Date",
                            selection: fixedStartBinding,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "Start",
                            selection: fixedStartBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        DatePicker(
                            "End",
                            selection: $fixedEnd,
                            in: fixedStart.addingTimeInterval(60)...,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                    }

                    if !hasFixedEvent {
                        Toggle("Deadline", isOn: $hasDeadline)
                        if hasDeadline {
                            DatePicker(
                                "Date",
                                selection: $deadline,
                                displayedComponents: .date
                            )
                            DatePicker(
                                "Time",
                                selection: $deadline,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
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
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Category", text: $category)
                            .accessibilityIdentifier("categoryField")
                        ForEach(categorySuggestions, id: \.self) { suggestion in
                            Button {
                                category = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("categorySuggestion_\(suggestion)")
                        }
                    }
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
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(saveButtonTitle)
                        }
                    }
                    .disabled(isSaving || trimmedTitle.isEmpty)
                    .accessibilityIdentifier("saveTaskButton")
                }
            }
            .sheet(isPresented: $showPositionSheet) {
                if let created = createdTask {
                    PositionTaskSheet(
                        taskTitle: created.title,
                        existingTasks: taskService.tasks,
                        onPositioned: { referenceTask, before in
                            Task { await repositionTask(created, relativeTo: referenceTask, before: before) }
                        },
                        onSkip: { dismiss() }
                    )
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
        guard !hasFixedEvent || fixedEnd > fixedStart else {
            errorMessage = "Fixed event end must be after its start."
            return
        }
        isSaving = true
        defer { isSaving = false }

        let deadlineValue = hasDeadline ? deadline : nil
        let startAtValue = hasFixedEvent ? fixedStart : nil
        let endAtValue = hasFixedEvent ? fixedEnd : nil
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
                    startAt: startAtValue,
                    endAt: endAtValue,
                    priority: priority,
                    status: status,
                    estimatedDuration: durationValue,
                    category: categoryValue,
                    notes: notesValue,
                    repeatWeekdays: repeatWeekdaysValue
                )
                createdTask = created
                showPositionSheet = true
            case .edit(let task):
                var updated = task
                updated.title = trimmedTitle
                updated.description = descriptionValue
                updated.deadline = deadlineValue
                updated.startAt = startAtValue
                updated.endAt = endAtValue
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

    private func repositionTask(_ task: TaskItem, relativeTo reference: TaskItem, before: Bool) async {
        let cal = Calendar.current
        let refDeadline = reference.deadline ?? Date()
        let newDeadline: Date

        if before {
            newDeadline = cal.date(byAdding: .day, value: -1, to: refDeadline) ?? refDeadline
        } else {
            newDeadline = cal.date(byAdding: .day, value: 1, to: refDeadline) ?? refDeadline
        }

        var updated = task
        updated.deadline = newDeadline
        do {
            _ = try await taskService.updateTask(updated)
            onSaved?(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
        dismiss()
    }
}
