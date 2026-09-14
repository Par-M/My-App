import SwiftUI

struct ReflectionCard: View {
    let reflection: Reflection
    let onRequestAnalysis: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(reflection.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                Spacer()
                Menu {
                    Button {
                        onRequestAnalysis(reflection.id)
                    } label: {
                        Label("Ask Gemini for insight", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Text(reflection.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let analysis = reflection.analysis, !analysis.isEmpty {
                Label(analysis, systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
