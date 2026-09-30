import SwiftUI

struct ReflectionCard: View {
    let reflection: Reflection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reflection.date, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)

            Text(reflection.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
