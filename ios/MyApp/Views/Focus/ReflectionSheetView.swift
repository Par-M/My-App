import SwiftUI

struct ReflectionSheetView: View {
    @Environment(FocusService.self) private var focus
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("How was today?") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Note what you focused on, what got in the way, and how you felt. Gemini will reflect back an insight.")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if let errorMessage = focus.errorMessage, !errorMessage.isEmpty {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Daily reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await focus.createReflection(date: .now, text: trimmed)
        dismiss()
    }
}
