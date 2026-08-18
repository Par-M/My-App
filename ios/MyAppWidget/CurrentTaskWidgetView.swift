import SwiftUI
import WidgetKit

struct CurrentTaskWidgetView: View {
    let entry: CurrentTaskEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
                .containerBackground(for: .widget) { Color.clear }
        default:
            rectangularView
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title = entry.title, !entry.noTask {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let end = entry.taskEnd {
                    let mins = max(0, Int(end.timeIntervalSince(Date()) / 60))
                    let hrs = mins / 60
                    let m = mins % 60
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(hrs > 0 ? "\(hrs)h \(m)m left" : "\(m)m left")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
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
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
                .containerBackground(for: .widget) { Color.clear }
        default:
            rectangularView
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
                Text("\(entry.tasksRemaining)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Text(entry.tasksRemaining == 1 ? "task left" : "tasks left")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let workEnd = entry.workEndDate {
                let mins = max(0, Int(workEnd.timeIntervalSince(Date()) / 60))
                let hrs = mins / 60
                let m = mins % 60
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(hrs > 0 ? "\(hrs)h \(m)m in day" : "\(m)m in day")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview(as: .accessoryRectangular) {
    CurrentTaskWidget()
} timeline: {
    CurrentTaskEntry(date: .now, title: "Write report", taskEnd: Date().addingTimeInterval(5400), tasksRemaining: 3, workEndDate: Date().addingTimeInterval(28800), noTask: false)
}

#Preview(as: .accessoryRectangular) {
    TasksRemainingWidget()
} timeline: {
    CurrentTaskEntry(date: .now, title: "Write report", taskEnd: Date().addingTimeInterval(5400), tasksRemaining: 3, workEndDate: Date().addingTimeInterval(28800), noTask: false)
}
