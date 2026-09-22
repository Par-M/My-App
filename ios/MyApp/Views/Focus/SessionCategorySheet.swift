import SwiftUI

struct SessionCategorySheet: View {
    let categories: [String]
    var logSession: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customCategory = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section("What did you complete?") {
                    Button {
                        log(nil)
                    } label: {
                        Label("Skip for now", systemImage: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if !categories.isEmpty {
                    Section("Categories") {
                        ForEach(categories, id: \.self) { category in
                            Button {
                                log(category)
                            } label: {
                                Text(category)
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Add another category", text: $customCategory)
                            .submitLabel(.done)
                            .onSubmit { log(customCategory) }
                        if !customCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                log(customCategory)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                    }
                } header: {
                    Text("Or add a new category")
                }
            }
            .navigationTitle("Log focus session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        log(nil)
                    }
                }
            }
            .disabled(isSaving)
        }
        .presentationDetents([.medium])
    }

    private func log(_ category: String?) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await logSession(category)
            dismiss()
        }
    }
}

#Preview {
    SessionCategorySheet(categories: ["Work", "Study", "Home"]) { _ in }
}