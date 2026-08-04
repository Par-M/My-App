import SwiftUI

struct BlockTimeEditorView: View {
    let block: CalendarBlock

    @Environment(ScheduleService.self) private var scheduleService
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var end: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(block: CalendarBlock) {
        self.block = block
        _start = State(initialValue: block.startAt)
        _end = State(initialValue: block.endAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    Text(block.title)
                }
                Section("Time") {
                    DatePicker("Start", selection: $start)
                    DatePicker("End", selection: $end)
                    if start >= end {
                        Text("End must be after start")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await delete() }
                    } label: {
                        Text("Delete Block")
                    }
                    .disabled(isSaving)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(start >= end || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await scheduleService.updateBlockTime(block, start: start, end: end)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await scheduleService.deleteBlock(block)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    BlockTimeEditorView(
        block: CalendarBlock(
            id: UUID(),
            userId: UUID(),
            taskId: UUID(),
            calendarEventId: nil,
            title: "Write report",
            startAt: Date(),
            endAt: Date().addingTimeInterval(3600),
            createdAt: Date(),
            updatedAt: Date()
        )
    )
    .environment(ScheduleService())
}
