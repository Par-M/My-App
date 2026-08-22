import SwiftUI
import WidgetKit

struct CurrentTaskWidgetView: View {
    let entry: CurrentTaskEntry

    var body: some View {
        rectangularView
            .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.topTaskTitles.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text("All clear")
                        .font(.system(size: 13, weight: .medium))
                }
            } else {
                ForEach(Array(entry.topTaskTitles.enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(index == 0 ? Color.orange : Color.secondary.opacity(0.4))
                            .frame(width: index == 0 ? 6 : 5, height: index == 0 ? 6 : 5)
                        Text(title)
                            .font(.system(size: index == 0 ? 13 : 11, weight: index == 0 ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                }
            }
        }
    }
}

struct TasksRemainingWidgetView: View {
    let entry: CurrentTaskEntry

    var body: some View {
        rectangularView
            .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.orange)
                    .font(.system(size: 10))
                Text("\(entry.tasksRemaining)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Text(entry.tasksRemaining == 1 ? "task" : "tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.system(size: 10))
                Text("\(entry.habitsRemaining)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Text(entry.habitsRemaining == 1 ? "habit" : "habits")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
