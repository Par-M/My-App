import WidgetKit
import SwiftUI

struct FocusTimerEntry: TimelineEntry {
    let date: Date
    let startedAt: TimeInterval
    let title: String?
}

struct FocusTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusTimerEntry {
        FocusTimerEntry(date: Date(), startedAt: Date().timeIntervalSince1970 - 600, title: "Deep Work Session")
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusTimerEntry) -> Void) {
        completion(snapshotEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusTimerEntry>) -> Void) {
        let data = WidgetDataStore.read()

        guard data.isFocusRunning else {
            let entry = FocusTimerEntry(date: Date(), startedAt: 0, title: data.focusTitle)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
            return
        }

        let calendar = Calendar.current
        var entries: [FocusTimerEntry] = [FocusTimerEntry(
            date: Date(),
            startedAt: data.focusStartedAt,
            title: data.focusTitle
        )]
        var date = Date()
        for _ in 0..<60 {
            date = calendar.date(byAdding: .minute, value: 1, to: date) ?? date.addingTimeInterval(60)
            entries.append(FocusTimerEntry(date: date, startedAt: data.focusStartedAt, title: data.focusTitle))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func snapshotEntry() -> FocusTimerEntry {
        let data = WidgetDataStore.read()
        return FocusTimerEntry(date: Date(), startedAt: data.focusStartedAt, title: data.focusTitle)
    }
}

struct FocusTimerWidget: Widget {
    let kind = "FocusTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusTimerProvider()) { entry in
            FocusTimerWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus Timer")
        .description("A live timer for your running focus session.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct FocusTimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusTimerEntry

    private var isRunning: Bool { entry.startedAt > 0 }

    private static let startFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.075, green: 0.082, blue: 0.11),
                    Color(red: 0.13, green: 0.09, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.075, green: 0.082, blue: 0.11),
                    Color(red: 0.13, green: 0.09, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(URL(string: "app://focus"))
    }

    private var accent: Color {
        Color(red: 1.0, green: 0.55, blue: 0.28)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                Text("FOCUS SESSION")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.white.opacity(0.8))
                Spacer()
                statusPill
            }

            Spacer(minLength: 18)

            if isRunning {
                Text(Date(timeIntervalSince1970: entry.startedAt), style: .timer)
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    Text(entry.title ?? "Deep Work Session")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                    Spacer()
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text("Started \(Self.startFormatter.string(from: Date(timeIntervalSince1970: entry.startedAt)))")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.55))
            } else {
                Text("00:00")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.35))

                Spacer(minLength: 12)

                Label("Start a focus session", systemImage: "timer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 8)

                Text("Open Lock In Bud to begin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(isRunning ? (entry.title ?? "Deep Work Session") : "Focus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(isRunning ? "Running" : "Idle")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(isRunning ? accent : Color.white.opacity(0.45))
            }

            Spacer(minLength: 8)

            if isRunning {
                Text(Date(timeIntervalSince1970: entry.startedAt), style: .timer)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text("00:00")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? accent : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(isRunning ? "LIVE" : "IDLE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}