import SwiftUI

struct PreferencesView: View {
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(\.dismiss) private var dismiss

    @State private var workStart: Double = 9
    @State private var workEnd: Double = 17
    @State private var buffer = 15
    @State private var energy = 3
    @State private var maxDailyHours = 8
    @State private var defaultDuration = 30
    @State private var defaultPriority: TaskPriority = .medium
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Work Hours") {
                    Stepper(value: $workStart, in: 0...24, step: 0.5) {
                        Text("Start: \(hourText(workStart))")
                    }
                    Stepper(value: $workEnd, in: 0...24, step: 0.5) {
                        Text("End: \(hourText(workEnd))")
                    }
                }
                Section("Scheduling") {
                    Stepper(value: $buffer, in: 0...120, step: 5) {
                        Text("Buffer: \(buffer) min")
                    }
                    Picker("Energy Level", selection: $energy) {
                        ForEach(1...5, id: \.self) { level in
                            Text("\(level)").tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $maxDailyHours, in: 1...16) {
                        Text("Max daily hours: \(maxDailyHours)")
                    }
                    Stepper(value: $defaultDuration, in: 5...480, step: 5) {
                        Text("Default task duration: \(defaultDuration) min")
                    }
                    Picker("Default Priority", selection: $defaultPriority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Save Preferences") {
                        Task { await save() }
                    }
                    .disabled(!isLoaded)
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await scheduleService.loadPreferences()
                if let pref = scheduleService.preference {
                    workStart = pref.workHoursStart
                    workEnd = pref.workHoursEnd
                    buffer = pref.bufferMinutes
                    energy = pref.energyLevel
                    maxDailyHours = pref.maxDailyHours
                    defaultDuration = pref.defaultDurationMinutes
                    defaultPriority = TaskPriority(rawValue: pref.defaultPriority) ?? .medium
                }
                isLoaded = true
            }
        }
    }

    private func hourText(_ value: Double) -> String {
        let hour = Int(value)
        let minutes = Int((value - Double(hour)) * 60)
        if hour >= 24 {
            return "24:00"
        }
        return String(format: "%d:%02d", hour, minutes)
    }

    private func save() async {
        let update = UserPreferenceUpdate(
            workHoursStart: workStart,
            workHoursEnd: workEnd,
            bufferMinutes: buffer,
            energyLevel: energy,
            maxDailyHours: maxDailyHours,
            defaultDurationMinutes: defaultDuration,
            defaultPriority: defaultPriority.rawValue
        )
        await scheduleService.updatePreferences(update)
        dismiss()
    }
}

#Preview {
    PreferencesView()
        .environment(ScheduleService())
}
