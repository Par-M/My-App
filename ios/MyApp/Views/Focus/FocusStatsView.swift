import Charts
import SwiftUI

struct FocusStatsView: View {
    @Environment(FocusService.self) private var focus
    @Environment(\.dismiss) private var dismiss

    private enum Granularity: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"
        var id: String { rawValue }
    }

    @State private var granularity: Granularity = .day
    @State private var editingSession: FocusSession?

    private var sessions: [FocusSession] { focus.dailySessions }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Granularity", selection: $granularity) {
                        ForEach(Granularity.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if sessions.isEmpty {
                        ContentUnavailableView(
                            "No focus sessions yet",
                            systemImage: "timer",
                            description: Text("Start a focus session and it will show up here.")
                        )
                    } else {
                        chartCard

                        legendCard

                        sessionsPerCategoryCard

                        sessionsListCard
                    }
                }
                .padding()
            }
            .navigationTitle("Focus stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingSession) { session in
                FocusSessionEditSheet(session: session)
            }
        }
        .presentationDetents([.large])
    }

    private var sessionsListCard: some View {
        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
        return VStack(alignment: .leading, spacing: 8) {
            Text("All sessions")
                .font(.headline)
            ForEach(sorted) { session in
                Button {
                    editingSession = session
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Self.color(for: session.category ?? "Uncategorized"))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.sessionFormatter.string(from: session.startedAt))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(timeRange(for: session))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(session.durationSeconds / 60) min")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                }
            }
            .accessibilityIdentifier("focusSessionList")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private static let sessionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func timeRange(for session: FocusSession) -> String {
        "\(Self.timeOnlyFormatter.string(from: session.startedAt)) – \(Self.timeOnlyFormatter.string(from: session.endedAt))"
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(granularity == .day ? "Minutes focused each day" : "Minutes focused each week")
                .font(.headline)

            Chart(entries) { entry in
                BarMark(
                    x: .value("Bucket", entry.bucket),
                    y: .value("Minutes", entry.minutes)
                )
                .foregroundStyle(Self.color(for: entry.category))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: categories) { category in
                Self.color(for: category)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let bucket = value.as(Date.self) {
                            Text(granularity == .day ? bucketLabel(bucket) : weekLabel(bucket))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.headline)
            ForEach(categories, id: \.self) { category in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Self.color(for: category))
                        .frame(width: 12, height: 12)
                    Text(category)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sessionsPerCategoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions per category")
                .font(.headline)
            ForEach(perCategoryTotals, id: \.category) { total in
                HStack {
                    Circle()
                        .fill(Self.color(for: total.category))
                        .frame(width: 10, height: 10)
                    Text(total.category)
                    Spacer()
                    Text("\(total.count) session\(total.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Text("\(total.minutes) min")
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                        .frame(minWidth: 56, alignment: .trailing)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data

    private var categories: [String] {
        let all = Set(sessions.compactMap { $0.category })
        return all.sorted()
    }

    private var longestBucket: Int {
        granularity == .day ? 28 : 8
    }

    private struct Entry: Identifiable {
        let id = UUID()
        let bucket: Date
        let category: String
        let minutes: Int
    }

    private var entries: [Entry] {
        let calendar = Calendar.current
        var result: [Entry] = []
        if granularity == .day {
            let buckets = dailyBuckets
            for bucket in buckets {
                let daySessions = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: bucket) }
                let totalsByCategory = totalMinutes(daySessions)
                for (category, minutes) in totalsByCategory {
                    result.append(Entry(bucket: bucket, category: category, minutes: minutes))
                }
            }
        } else {
            for bucket in weeklyBuckets {
                let weekSessions = sessions.filter { session in
                    calendar.isDate(session.startedAt, equalTo: bucket, toGranularity: .weekOfYear)
                }
                let totalsByCategory = totalMinutes(weekSessions)
                for (category, minutes) in totalsByCategory {
                    result.append(Entry(bucket: bucket, category: category, minutes: minutes))
                }
            }
        }
        return result
    }

    private func totalMinutes(_ slice: [FocusSession]) -> [(String, Int)] {
        let grouped = Dictionary(grouping: slice, by: { $0.category ?? "Uncategorized" })
        return grouped
            .map { key, value in (key, value.reduce(0) { $0 + $1.durationSeconds } / 60) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    private var dailyBuckets: [Date] {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -(longestBucket - 1), to: now) ?? now
        var buckets: [Date] = []
        var date = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: now)
        while date <= end {
            buckets.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return buckets
    }

    private var weeklyBuckets: [Date] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        var buckets: [Date] = []
        for offset in stride(from: -(longestBucket - 1), through: 0, by: 1) {
            if let interval = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeek.start) ?? thisWeek.start) {
                buckets.append(interval.start)
            }
        }
        return buckets
    }

    private var bucketsNeeded: [Date] {
        granularity == .day ? dailyBuckets : weeklyBuckets
    }

    private func bucketLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func weekLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let weekNumber = calendar.component(.weekOfYear, from: date)
        return "W\(weekNumber)"
    }

    private struct CategoryTotal: Identifiable {
        let id = UUID()
        let category: String
        let count: Int
        let minutes: Int
    }

    private var perCategoryTotals: [CategoryTotal] {
        let grouped = Dictionary(grouping: sessions, by: { $0.category ?? "Uncategorized" })
        return grouped
            .map { group in
                CategoryTotal(
                    category: group.key,
                    count: group.value.count,
                    minutes: group.value.reduce(0) { $0 + $1.durationSeconds } / 60
                )
            }
            .sorted { $0.minutes > $1.minutes }
    }

    // MARK: - Color

    private static let palette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .red, .indigo, .brown, .mint,
    ]

    static func color(for category: String) -> Color {
        let index = abs(category.hashValue) % palette.count
        return palette[index]
    }
}

#Preview {
    FocusStatsView()
        .environment(FocusService())
}