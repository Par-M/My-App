import SwiftUI

/// A 15-minute-step slider showing how much of a task's estimated duration has
/// been completed. "Amount left" = estimated minus completed.
///
/// Changes are committed to the parent (persisted) when the user finishes
/// dragging so we don't send a network request on every 15-minute step.
struct CompletenessSlider: View {
    let estimatedMinutes: Int

    @Binding var completedMinutes: Int
    var onCommit: (Int) -> Void

    private var amountLeft: Int {
        max(0, estimatedMinutes - completedMinutes)
    }

    private var maxValue: Double {
        Double(max(15, estimatedMinutes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(formatMinutes(completedMinutes)) done")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(formatMinutes(amountLeft)) left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(completedMinutes) },
                    set: { completedMinutes = Int($0) }
                ),
                in: 0...maxValue,
                step: 15,
                onEditingChanged: { editing in
                    if !editing {
                        onCommit(completedMinutes)
                    }
                }
            )

            HStack {
                Text("0")
                Spacer()
                Text(formatMinutes(estimatedMinutes))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
