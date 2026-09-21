import SwiftUI

struct TaskChecklistEditor: View {
    @Binding var items: [ChecklistItem]
    var onSave: () -> Void

    @State private var newItem = ""

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            HStack(spacing: 10) {
                Button {
                    items[index].done.toggle()
                    onSave()
                } label: {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.done ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.done ? "Mark as not done" : "Mark as done")

                TextField(
                    "Checklist item",
                    text: Binding(
                        get: { items[index].text },
                        set: { items[index] = ChecklistItem(text: $0, done: items[index].done) }
                    )
                )
                .strikethrough(item.done, color: .secondary)
                .foregroundStyle(item.done ? Color.secondary : Color.primary)
                .onSubmit(onSave)
            }
            .swipeActions {
                Button("Delete", role: .destructive) {
                    items.remove(at: index)
                    onSave()
                }
            }
        }

        HStack {
            TextField("Add a checklist item…", text: $newItem)
                .submitLabel(.done)
                .onSubmit(commit)
            Button(action: commit) {
                Image(systemName: "plus.circle.fill")
            }
            .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func commit() {
        let trimmed = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(ChecklistItem(text: trimmed))
        newItem = ""
        onSave()
    }
}