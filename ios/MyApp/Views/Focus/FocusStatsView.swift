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
    @State private var selectedCategory: String?

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
                    Section("Category spread") {
                        radarCard
                            .id(granularity)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("Sessions per category") {
                        sessionsPerCategoryCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        if selectedCategory != nil {
                            Button {
                                withAnimation(.snappy(duration: 0.25)) {
                                    selectedCategory = nil
                                }
                            } label: {
                                Label("Show all sessions", systemImage: "xmark.circle.fill")
                                    .font(.footnote)
                            }
                        }
                        ForEach(filteredSessions) { session in
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
                    } header: {
                        Text(sessionSectionTitle)
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

private var filteredSessions: [FocusSession] {
    guard let selectedCategory else { return sorted }
    return sorted.filter {
        ($0.category ?? "Uncategorized") == selectedCategory
    }
}

private var sessionSectionTitle: String {
    guard let selectedCategory else { return "All sessions" }
    return "\(selectedCategory) sessions"
}

private func deleteSessions(at offsets: IndexSet) {
    let toDelete = offsets.map { filteredSessions[$0] }
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

    // MARK: - Radar card

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Time per category")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FocusChartColors.primaryText)
                Spacer()
                Text(windowLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FocusChartColors.secondaryText)
            }

            FocusRadarChart(
                entries: radarEntries,
                selectedCategory: selectedCategory
            ) { category in
                withAnimation(.snappy(duration: 0.25)) {
                    selectedCategory = category
                }
            }

            if let selectedCategory,
               let total = radarTotals[selectedCategory] {
                radarSelectionDetail(category: selectedCategory, minutes: total)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusChartColors.chartBackground, in: RoundedRectangle(cornerRadius: 16))
        .animation(.snappy(duration: 0.25), value: selectedCategory)
    }

    private func radarSelectionDetail(category: String, minutes: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(FocusChartColors.color(for: category))
                .frame(width: 12, height: 12)
            Text(category)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FocusChartColors.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(minutes) min")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FocusChartColors.primaryText)
                    .monospacedDigit()
                Text(windowLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FocusChartColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            FocusChartColors.color(for: category).opacity(0.18),
            in: RoundedRectangle(cornerRadius: 10)
        )
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

    // MARK: - Radar data

    private var windowStart: Date {
        let calendar = Calendar.current
        let now = Date()
        if usesDailyBuckets {
            return calendar.date(
                byAdding: .day,
                value: -(dayCount - 1),
                to: calendar.startOfDay(for: now)
            ) ?? calendar.startOfDay(for: now)
        }
        let weekCount = self.weekCount
        guard weekCount > 0,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        else { return calendar.startOfDay(for: now) }
        return calendar.date(
            byAdding: .weekOfYear,
            value: -(weekCount - 1),
            to: thisWeek.start
        ) ?? thisWeek.start
    }

    private var windowLabel: String {
        switch granularity {
        case .oneDay: "Today"
        case .threeDays: "Last 3 days"
        case .week: "Last 7 days"
        case .twoWeeks: "Last 2 weeks"
        case .fourWeeks: "Last 4 weeks"
        }
    }

    private var radarTotals: [String: Int] {
        var totals: [String: Int] = [:]
        for session in sessions where session.startedAt >= windowStart {
            let category = session.category ?? "Uncategorized"
            totals[category, default: 0] += session.durationSeconds / 60
        }
        return totals
    }

    private var radarEntries: [FocusRadarEntry] {
        radarTotals
            .map { FocusRadarEntry(category: $0.key, minutes: $0.value) }
            .sorted { $0.minutes > $1.minutes }
    }
}

private struct FocusRadarEntry: Identifiable, Equatable {
    let category: String
    let minutes: Int
    var id: String { category }
}

// MARK: - Colors

enum FocusChartColors {
    static let chartBackground = Color(red: 0.086, green: 0.094, blue: 0.12)
    static let primaryText = Color.white.opacity(0.9)
    static let secondaryText = Color.white.opacity(0.55)
    static let skyBlue = Color(red: 0.32, green: 0.66, blue: 0.93)

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

// MARK: - Radar chart

private struct FocusRadarChart: View {
    let entries: [FocusRadarEntry]
    var selectedCategory: String? = nil
    var onSelect: (String) -> Void

    private let size: CGFloat = 280
    private let maxRadius: CGFloat = 88

    private var maxMinutes: Int {
        entries.map(\.minutes).max() ?? 1
    }

    var body: some View {
        let count = entries.count
        ZStack {
            if count > 0 {
                radarGrid(count: count)
                radarArea(count: count)
                radarPoints(count: count)
                axisLabels(count: count)
            } else {
                Text("No sessions in this window")
                    .font(.caption)
                    .foregroundStyle(FocusChartColors.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
    }

    private func point(count: Int, index: Int, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2
            + Double(index) * 2 * Double.pi / Double(max(count, 1))
        return CGPoint(
            x: size / 2 + radius * cos(angle),
            y: size / 2 + radius * sin(angle)
        )
    }

    private func radarGrid(count: Int) -> some View {
        ZStack {
            ForEach(1...4, id: \.self) { level in
                RadarGridPolygon(
                    count: count,
                    radius: maxRadius * CGFloat(level) / 4,
                    point: point
                )
                .stroke(
                    Color.white.opacity(level == 4 ? 0.25 : 0.1),
                    lineWidth: 1
                )
            }
            if count > 1 {
                ForEach(0..<count, id: \.self) { index in
                    Path { path in
                        path.move(to: CGPoint(x: size / 2, y: size / 2))
                        path.addLine(to: point(count: count, index: index, radius: maxRadius))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
        }
    }

    private func radarArea(count: Int) -> some View {
        let points = entries.enumerated().map { index, entry in
            point(
                count: count,
                index: index,
                radius: maxRadius * CGFloat(entry.minutes) / CGFloat(maxMinutes)
            )
        }
        let isSelected = selectedCategory != nil

        return RadarArea(points: points)
            .fill(
                isSelected == false
                    ? LinearGradient(
                        colors: [
                            FocusChartColors.skyBlue.opacity(0.45),
                            FocusChartColors.skyBlue.opacity(0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [
                            FocusChartColors.color(for: selectedCategory ?? "").opacity(0.4),
                            FocusChartColors.color(for: selectedCategory ?? "").opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
            )
            .overlay(
                RadarArea(points: points)
                    .stroke(
                        isSelected == false
                            ? FocusChartColors.skyBlue.opacity(0.85)
                            : FocusChartColors.color(for: selectedCategory ?? "").opacity(0.9),
                        lineWidth: 1.8
                    )
            )
            .animation(.snappy(duration: 0.25), value: selectedCategory)
    }

    private func radarPoints(count: Int) -> some View {
        ForEach(entries) { entry in
            let index = entries.firstIndex(of: entry) ?? 0
            let radius = maxRadius * CGFloat(entry.minutes) / CGFloat(maxMinutes)
            let isSelected = selectedCategory == entry.category
            Button {
                onSelect(entry.category)
            } label: {
                Circle()
                    .fill(FocusChartColors.color(for: entry.category))
                    .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.white : Color.white.opacity(0.85),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(color: FocusChartColors.color(for: entry.category).opacity(0.6), radius: 3)
            }
            .buttonStyle(.plain)
            .position(point(count: count, index: index, radius: radius))
            .accessibilityLabel("Show \(entry.category) sessions")
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
    }

    private func axisLabels(count: Int) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            let angle = -Double.pi / 2
                + Double(index) * 2 * Double.pi / Double(max(count, 1))
            let labelRadius = maxRadius + 22
            let isSelected = selectedCategory == entry.category
            Button {
                onSelect(entry.category)
            } label: {
                Text(entry.category)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected
                            ? FocusChartColors.color(for: entry.category)
                            : FocusChartColors.secondaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
            .position(
                CGPoint(
                    x: size / 2 + labelRadius * cos(angle),
                    y: size / 2 + labelRadius * sin(angle)
                )
            )
            .accessibilityLabel("Show \(entry.category) sessions")
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
    }
}

private struct RadarGridPolygon: Shape {
    let count: Int
    let radius: CGFloat
    var point: (Int, Int, CGFloat) -> CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count > 1 else { return path }
        for index in 0..<count {
            let p = point(count, index, radius)
            if index == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct RadarArea: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() {
            path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    FocusStatsView()
        .environment(FocusService())
}