import SwiftUI

struct FocusStatsView: View {
    @Environment(FocusService.self) private var focus
    @Environment(\.dismiss) private var dismiss

    private enum Granularity: String, CaseIterable, Identifiable {
        case oneDay = "1 Day"
        case threeDays = "3 Days"
        case week = "1 Week"
        case twoWeeks = "2 Weeks"
        case fourWeeks = "4 Weeks"
        var id: String { rawValue }
    }

    @State private var granularity: Granularity = .oneDay
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
                            .id(granularity)
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
                                        .fill(FocusChartColors.color(for: session.category ?? "Uncategorized"))
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
                    Picker("Granularity", selection: Binding(
                        get: { granularity },
                        set: { newValue in
                            withAnimation(.snappy(duration: 0.35)) {
                                granularity = newValue
                            }
                        }
                    )) {
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

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Minutes focused")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FocusChartColors.primaryText)
                Spacer()
                Text("\(totalMinutes) min total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FocusChartColors.secondaryText)
            }

            FocusBarChart(
                items: chartItems,
                maxMinutes: maxMinutes,
                totalMinutes: totalMinutes
            )

            FocusChartLegend(categories: categories)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusChartColors.chartBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private var totalMinutes: Int {
        chartItems.reduce(0) { $0 + $1.totalMinutes }
    }

    // MARK: - Sessions per category

    private var sessionsPerCategoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions per category")
                .font(.headline)
            ForEach(perCategoryTotals, id: \.category) { total in
                HStack {
                    Circle()
                        .fill(FocusChartColors.color(for: total.category))
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
        var all = Set(sessions.compactMap { $0.category })
        if sessions.contains(where: { $0.category == nil }) {
            all.insert("Uncategorized")
        }
        return all.sorted()
    }

    private var usesDailyBuckets: Bool {
        switch granularity {
        case .oneDay, .threeDays, .week: true
        case .twoWeeks, .fourWeeks: false
        }
    }

    private var dayCount: Int {
        switch granularity {
        case .oneDay: 1
        case .threeDays: 3
        case .week: 7
        default: 0
        }
    }

    private var weekCount: Int {
        switch granularity {
        case .twoWeeks: 2
        case .fourWeeks: 4
        default: 0
        }
    }

    private var chartItems: [FocusChartItem] {
        let calendar = Calendar.current
        let daily = usesDailyBuckets
        let bucketDates: [Date] = daily
            ? dailyBuckets(dayCount: dayCount)
            : weeklyBuckets(weekCount: weekCount)
        guard !categories.isEmpty else { return [] }

        var totals: [Date: [String: Int]] = [:]
        for date in bucketDates { totals[date] = [:] }
        for session in sessions {
            let date: Date
            if daily {
                date = calendar.startOfDay(for: session.startedAt)
            } else {
                date = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start
                    ?? calendar.startOfDay(for: session.startedAt)
            }
            let category = session.category ?? "Uncategorized"
            totals[date, default: [:]][category, default: 0] += session.durationSeconds / 60
        }

        let isOneDay = granularity == .oneDay
        return bucketDates.map { date in
            FocusChartItem(
                date: date,
                label: isOneDay ? "Today" : (daily ? Self.dailyLabel(date) : Self.weeklyLabel(date)),
                isToday: daily ? calendar.isDateInToday(date)
                    : (self.currentWeekStart == date),
                segments: categories.map { category in
                    FocusChartSegment(
                        category: category,
                        minutes: totals[date]?[category] ?? 0
                    )
                }
            )
        }
    }

    private var currentWeekStart: Date? {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start
    }

    private var maxMinutes: Int {
        chartItems.map(\.totalMinutes).max() ?? 0
    }

    private func dailyBuckets(dayCount: Int) -> [Date] {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now
        var buckets: [Date] = []
        var date = calendar.startOfDay(for: start)
        while date <= calendar.startOfDay(for: now) {
            buckets.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return buckets
    }

    private func weeklyBuckets(weekCount: Int) -> [Date] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        var buckets: [Date] = []
        for offset in stride(from: -(weekCount - 1), through: 0, by: 1) {
            if let interval = calendar.dateInterval(
                of: .weekOfYear,
                for: calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeek.start) ?? thisWeek.start
            ) {
                buckets.append(interval.start)
            }
        }
        return buckets
    }

    private static let dayAxisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter
    }()

    private static let weekRangeMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static func dailyLabel(_ date: Date) -> String {
        dayAxisFormatter.string(from: date)
    }

    static func weeklyLabel(_ start: Date) -> String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(weekRangeMonthFormatter.string(from: start))–\(weekRangeMonthFormatter.string(from: end))"
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
}

// MARK: - Chart models

private struct FocusChartItem: Identifiable {
    let date: Date
    let label: String
    let isToday: Bool
    let segments: [FocusChartSegment]
    var id: Date { date }
    var totalMinutes: Int { segments.reduce(0) { $0 + $1.minutes } }
}

private struct FocusChartSegment: Identifiable {
    let category: String
    let minutes: Int
    var id: String { category }
}

// MARK: - Colors

enum FocusChartColors {
    static let chartBackground = Color(red: 0.086, green: 0.094, blue: 0.12)
    static let primaryText = Color.white.opacity(0.9)
    static let secondaryText = Color.white.opacity(0.55)

    static let palette: [Color] = [
        Color(red: 0.93, green: 0.33, blue: 0.33), // coral red
        Color(red: 0.16, green: 0.63, blue: 0.60), // teal
        Color(red: 1.00, green: 0.84, blue: 0.20), // sunny yellow
        Color(red: 0.40, green: 0.45, blue: 0.87), // periwinkle
        Color(red: 1.00, green: 0.60, blue: 0.25), // orange
        Color(red: 0.75, green: 0.42, blue: 0.87), // orchid
        Color(red: 0.25, green: 0.78, blue: 0.45), // emerald
        Color(red: 0.92, green: 0.34, blue: 0.61), // magenta
        Color(red: 0.32, green: 0.66, blue: 0.93), // sky blue
        Color(red: 0.93, green: 0.78, blue: 0.55), // sand
        Color(red: 0.55, green: 0.37, blue: 0.30), // umber
        Color(red: 0.62, green: 0.83, blue: 0.44), // lime
        Color(red: 0.65, green: 0.36, blue: 0.55), // plum
        Color(red: 0.25, green: 0.55, blue: 0.82), // steel blue
        Color(red: 0.89, green: 0.47, blue: 0.67), // rose
        Color(red: 0.96, green: 0.68, blue: 0.35), // apricot
        Color(red: 0.38, green: 0.53, blue: 0.38), // olive
        Color(red: 0.50, green: 0.73, blue: 0.73), // seafoam
        Color(red: 0.73, green: 0.60, blue: 0.88), // lilac
        Color(red: 0.80, green: 0.74, blue: 0.40), // mustard
    ]

    static func color(for category: String) -> Color {
        let index = abs(category.hashValue) % palette.count
        return palette[index]
    }
}

// MARK: - Dark stacked bar chart

private struct FocusBarChart: View {
    let items: [FocusChartItem]
    let maxMinutes: Int
    let totalMinutes: Int

    private let barWidth: CGFloat = 22
    private let barSpacing: CGFloat = 14
    private let chartHeight: CGFloat = 168

    @State private var revealed = false

    var body: some View {
        let unit = maxMinutes > 0 ? chartHeight / CGFloat(maxMinutes) : 0
        ZStack(alignment: .topLeading) {
            gridLines

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: barSpacing) {
                    Spacer(minLength: 0)
                    ForEach(items) { item in
                        FocusBarColumn(
                            item: item,
                            unit: unit,
                            barWidth: barWidth,
                            chartHeight: chartHeight,
                            revealed: revealed
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(height: chartHeight + 26)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                revealed = true
            }
        }
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                if index < 4 {
                    Color.clear.frame(height: (chartHeight - 5) / 4)
                }
            }
        }
        .frame(height: chartHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct FocusBarColumn: View {
    let item: FocusChartItem
    let unit: CGFloat
    let barWidth: CGFloat
    let chartHeight: CGFloat
    let revealed: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottom) {
                if item.totalMinutes <= 0 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: barWidth * 0.5, height: 3)
                } else {
                    stackedSegments
                }
            }
            .frame(width: barWidth, height: chartHeight)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: revealed)

            Text(item.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    item.isToday ? FocusChartColors.primaryText : Color.white.opacity(0.5)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stackedSegments: some View {
        let bottomUp = Array(item.segments.reversed())
        var offsets: [CGFloat] = []
        var running: CGFloat = 0
        for segment in bottomUp {
            offsets.append(running)
            running += CGFloat(segment.minutes) * unit
        }

        return ZStack(alignment: .bottom) {
            ForEach(Array(bottomUp.enumerated()), id: \.element.id) { index, segment in
                let height = max(CGFloat(segment.minutes) * unit, 3)
                RoundedRectangle(cornerRadius: 3)
                    .fill(FocusChartColors.color(for: segment.category))
                    .frame(width: barWidth, height: revealed ? height : 0)
                    .offset(y: revealed ? -offsets[index] : 0)
            }
        }
    }
}

// MARK: - Legend

private struct FocusChartLegend: View {
    let categories: [String]

    private let columns = [
        GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .leading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(categories, id: \.self) { category in
                HStack(spacing: 6) {
                    Circle()
                        .fill(FocusChartColors.color(for: category))
                        .frame(width: 7, height: 7)
                    Text(category)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FocusChartColors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview {
    FocusStatsView()
        .environment(FocusService())
}