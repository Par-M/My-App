import SwiftUI
import WidgetKit
import AppIntents

struct CurrentTaskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CurrentTaskEntry

    var body: some View {
        switch family {
        case .systemLarge:
            largeLayout
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.16), Color.orange.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Large

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Today's Focus", systemImage: "star.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(entry.tasksRemaining) left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            if entry.topTaskTitles.isEmpty {
                emptyState
            } else {
                ForEach(Array(entry.topTaskTitles.prefix(6).enumerated()), id: \.offset) { index, title in
                    taskRow(title: title, index: index, isLarge: true)
                    if index < min(entry.topTaskTitles.count, 6) - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }

            Spacer(minLength: 4)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { background }
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Next up", systemImage: "star.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(entry.tasksRemaining) task\(entry.tasksRemaining == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if entry.topTaskTitles.isEmpty {
                emptyState
            } else {
                ForEach(Array(entry.topTaskTitles.prefix(3).enumerated()), id: \.offset) { index, title in
                    taskRow(title: title, index: index, isLarge: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { background }
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today", systemImage: "star.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)

            if entry.topTaskTitles.isEmpty {
                emptyState
            } else {
                taskRow(title: entry.topTaskTitles[0], index: 0, isLarge: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { background }
    }

    // MARK: - Shared bits

    private func taskRow(title: String, index: Int, isLarge: Bool) -> some View {
        HStack(spacing: 8) {
            if index == 0 {
                if #available(iOS 17.0, *) {
                    Button(intent: CompleteTopTaskIntent()) {
                        Image(systemName: "circle")
                            .font(.system(size: isLarge ? 16 : 13))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                }
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: isLarge ? 7 : 5, height: isLarge ? 7 : 5)
            }

            Text(title)
                .font(.system(
                    size: (isLarge ? 15 : 12) + (index == 0 ? 1 : 0),
                    weight: index == 0 ? .semibold : .regular
                ))
                .lineLimit(isLarge ? 2 : 1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            Text("All clear")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("\(entry.tasksRemaining)", systemImage: "checklist")
                .font(.system(size: 12, weight: .semibold))
            Label("\(entry.habitsRemaining)", systemImage: "checkmark.circle")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("Lock In Bud")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
    }
}

struct TasksRemainingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CurrentTaskEntry

    var body: some View {
        switch family {
        case .systemLarge:
            largeLayout
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color.teal.opacity(0.16), Color.teal.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func countRow(
        icon: String,
        iconColor: Color,
        count: Int,
        label: String,
        size: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.system(size: size * 0.4, weight: .semibold))
            Text("\(count)")
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .monospacedDigit()
            Text(label)
                .font(.system(size: size * 0.34))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Progress Today", systemImage: "chart.bar.fill")
                .font(.system(size: 15, weight: .bold))

            HStack(spacing: 24) {
                countRow(icon: "checklist", iconColor: .orange, count: entry.tasksRemaining, label: "tasks", size: 40)
                countRow(icon: "checkmark.circle", iconColor: .green, count: entry.habitsRemaining, label: "habits", size: 40)
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Next up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if entry.topTaskTitles.isEmpty {
                    Text("All clear — nothing pending.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(entry.topTaskTitles.prefix(4).enumerated()), id: \.offset) { index, title in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(index == 0 ? Color.orange : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                            Text(title)
                                .font(.system(size: 13, weight: index == 0 ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { background }
    }

    private var mediumLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                countRow(icon: "checklist", iconColor: .orange, count: entry.tasksRemaining, label: "tasks", size: 30)
                countRow(icon: "checkmark.circle", iconColor: .green, count: entry.habitsRemaining, label: "habits", size: 30)
            }
            Spacer()
            if let title = entry.topTaskTitles.first {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Top task")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { background }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            countRow(icon: "checklist", iconColor: .orange, count: entry.tasksRemaining, label: "tasks", size: 22)
            countRow(icon: "checkmark.circle", iconColor: .green, count: entry.habitsRemaining, label: "habits", size: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { background }
    }
}