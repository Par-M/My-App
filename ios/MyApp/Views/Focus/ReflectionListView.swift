import SwiftUI

struct ReflectionListView: View {
    @Environment(FocusService.self) private var focus
    @Environment(\.dismiss) private var dismiss

    @State private var showingComposer = false

    var body: some View {
        NavigationStack {
            List {
                if focus.reflections.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No reflections yet",
                            systemImage: "square.and.pencil",
                            description: Text("Take a moment each evening to review how your focus went.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Previous reflections") {
                        ForEach(focus.reflections) { reflection in
                            ReflectionCard(reflection: reflection) { id in
                                Task { await focus.requestAnalysis(reflectionID: id) }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                }

                Section {
                    Button {
                        showingComposer = true
                    } label: {
                        Label("Write today's reflection", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reflections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingComposer) {
                ReflectionSheetView()
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    ReflectionListView()
        .environment(FocusService())
}