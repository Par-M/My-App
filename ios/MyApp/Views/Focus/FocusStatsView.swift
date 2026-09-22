import Charts
import SwiftUI

struct FocusStatsView: View {
    @Environment(FocusService.self) private var focus
    @Environment(\.dismiss) private var dismiss

    private enum Granularity: String, CaseIterable, Identifiable {
        case threeDays = "3 Days"
        case week = "1 Week"
        case twoWeeks = "2 Weeks"
        case month = "Month"
        var id: String { rawValue }
    }

    @State private var granularity: Granularity = .threeDays
    @State private var editingSession: FocusSession?

    private var sessions: [FocusSession] { focus.dailySessions }

    private var sorted: [FocusSession] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No focus sessions yet",
                            systemImage: "timer",
                            description: Text("Start a focus session and it will show up here.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Minutes focused") {
                        chartCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("Categories") {
                        legendCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("Sessions per category") {
                        sessionsPerCategoryCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("All sessions") {
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
                            .accessibilityIdentifier("focusSessionRow")
                        }
                        .onDelete(perform: deleteSessions)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top, spacing: 8) {
                if !sessions.isEmpty {
                    Picker("Granularity", selection: $granularity) {
                        ForEach(Granularity.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
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

    private func deleteSessions(at offsets: IndexSet) {
        let toDelete = offsets.map { sorted[$0] }
        Task {
            for session in toDelete {
                await delete(session)
            }
        }
    }

    @discardableResult
    private func delete(_ session: FocusSession) async -> Bool {
        await focus.deleteSession(id: session.id)
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
            Text(usesDailyBuckets ? "Minutes focused each day" : "Minutes focused each week")
                .font(.headline)

            Chart(entries) { entry in
                LineMark(
                    x: .value("Bucket", entry.bucket),
                    y: .value("Minutes", entry.minutes),
                    series: .value("Category", entry.category)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Self.color(for: entry.category))
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                PointMark(
                    x: .value("Bucket", entry.bucket),
                    y: .value("Minutes", entry.minutes)
                )
                .symbolSize(18)
                .foregroundStyle(Self.color(for: entry.category))
            }
            .chartYScale(domain: 0...(maxMinutes + 5))
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let bucket = value.as(Date.self) {
                            Text(usesDailyBuckets ? bucketLabel(bucket) : weekLabel(bucket))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let minutes = value.as(Int.self) {
                            Text("\(minutes)")
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var usesDailyBuckets: Bool {
        granularity != .month
    }

    private var dayCount: Int {
        switch granularity {
        case .threeDays: 3
        case .week: 7
        case .twoWeeks: 14
        case .month: 0
        }
    }

    private var weekCount: Int {
        granularity == .month ? 5 : 0
    }

    private struct Entry: Identifiable {
        let id = UUID()
        let bucket: Date
        let category: String
        let minutes: Int
    }

    private var entries: [Entry] {
        let calendar = Calendar.current
        let buckets: [Date] = usesDailyBuckets
            ? dailyBuckets(dayCount: dayCount)
            : weeklyBuckets(weekCount: weekCount)
        guard !categories.isEmpty else { return [] }

        var totals: [String: Int] = [:]
        for session in sessions {
            let bucket: Date
            if usesDailyBuckets {
                bucket = calendar.startOfDay(for: session.startedAt)
            } else {
                bucket = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start ?? session.startedAt
            }
            let key = "\(bucket.timeIntervalSince1970)|\(session.category ?? "Uncategorized")"
            totals[key, default: 0] += session.durationSeconds / 60
        }

        var result: [Entry] = []
        for bucket in buckets {
            for category in categories {
                let key = "\(bucket.timeIntervalSince1970)|\(category)"
                result.append(Entry(bucket: bucket, category: category, minutes: totals[key] ?? 0))
            }
        }
        return result
    }

    private var maxMinutes: Int {
        entries.map(\.minutes).max() ?? 0
    }

    private func dailyBuckets(dayCount: Int) -> [Date] {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now
        var buckets: [Date] = []
        var date = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: now)
        while date <= end {
            buckets.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return buckets
    }

    private func weeklyBuckets(weekCount: Int) -> [Date] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        var buckets: [Date] = []
        for offset in stride(from: -(weekCount - 1), through: 0, by: 1) {
            if let interval = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeek.start) ?? thisWeek.start) {
                buckets.append(interval.start)
            }
        }
        return buckets
    }

    private func bucketLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDate(date, inSameDayAs: Date().addingTimeInterval(-24 * 3600)) {
            return "Yesterday"
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