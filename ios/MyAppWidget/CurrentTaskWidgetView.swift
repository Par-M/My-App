import SwiftUI
import WidgetKit

struct CurrentTaskWidgetView: View {
    let entry: CurrentTaskEntry

    var body: some View {
        rectangularView
            .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let current = entry.currentTaskTitle {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text(current)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let next = entry.nextTaskTitle {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 5, height: 5)
                        Text(next)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text("All clear")
                        .font(.system(size: 13, weight: .medium))
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
