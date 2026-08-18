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
            if let title = entry.title {
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
                    let cal = Calendar.current
                    let timeStr = end.formatted(date: .omitted, time: .shortened)
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("Complete by \(timeStr)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
                Text("\(entry.habitsDone)/\(entry.habitsTotal)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                Text("done")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if entry.habitsTotal > 0 {
                GeometryReader { geo in
                    let progress = CGFloat(entry.habitsDone) / CGFloat(max(entry.habitsTotal, 1))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quinary)
                            .frame(height: 5)
                        Capsule()
                            .fill(.green)
                            .frame(width: geo.size.width * progress, height: 5)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 5)
            } else {
                Text("No habits today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview(as: .accessoryRectangular) {
    CurrentTaskWidget()
} timeline: {
    CurrentTaskEntry(date: .now, title: "Write report", taskEnd: Date().addingTimeInterval(5400), habitsDone: 3, habitsTotal: 5)
}

#Preview(as: .accessoryRectangular) {
    TasksRemainingWidget()
} timeline: {
    CurrentTaskEntry(date: .now, title: "Write report", taskEnd: Date().addingTimeInterval(5400), habitsDone: 3, habitsTotal: 5)
}
