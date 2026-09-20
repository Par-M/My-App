import ActivityKit
import Charts
import SwiftUI

extension Notification.Name {
    static let openReflection = Notification.Name("openReflection")
}

struct FocusDashboardView: View {
    @Environment(FocusService.self) private var focus

    private enum RangeOption: String, CaseIterable, Identifiable {
        case day = "1D"
        case threeDays = "3D"
        case fiveDays = "5D"
        case week = "1W"
        case twoWeeks = "2W"
        case month = "4W"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .day: return 1
            case .threeDays: return 3
            case .fiveDays: return 5
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 28
            }
        }
        var dateStart: Date {
            Calendar.current.date(byAdding: .day, value: -(days - 1), to: .now) ?? .now
        }
        var periodLabel: String {
            switch self {
            case .day: return "today"
            case .threeDays: return "past 3 days"
            case .fiveDays: return "past 5 days"
            case .week: return "this week (7 days)"
            case .twoWeeks: return "past 14 days"
            case .month: return "past 4 weeks"
            }
        }
    }

    @State private var range: RangeOption = .week
    @State private var showingReflection = false
    @AppStorage("focusTimerStartedAt") private var timerStartedAtRef = 0.0
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?

    private var isTimerRunning: Bool { timerStartedAtRef > 0 }
    private var timerStartedAt: Date? {
        timerStartedAtRef > 0 ? Date(timeIntervalSince1970: timerStartedAtRef) : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage = focus.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    timerCard

                    summaryCard

                    chartCard

                    if let summary = focus.summary, let analysis = summary.analysis, !analysis.isEmpty {
                        analysisCard(analysis)
                    }

                    reflectionButton

                    reflectionsSection
                }
                .padding()
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await focus.loadFocus(after: range.dateStart, before: .now) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("refreshFocusButton")
                }
            }
            .sheet(isPresented: $showingReflection) {
                ReflectionSheetView()
            }
            .task {
                await focus.loadFocus(after: range.dateStart, before: .now)
            }
            .onChange(of: range) {
                Task { await focus.loadFocus(after: range.dateStart, before: .now) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openReflection)) { _ in
                showingReflection = true
            }
        }
    }

    private var timerCard: some View {
        let minutes = Int(elapsedSeconds / 60)
        let seconds = elapsedSeconds % 60
        return VStack(spacing: 12) {
            if isTimerRunning {
                Text(String(format: "%02d:%02d", minutes, seconds))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("focusTimerLabel")

                Button(role: .destructive) {
                    stopTimer()
                } label: {
                    Label("Stop & log session", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Text("Start a focus timer")
                    .font(.headline)
                Text("Track a deep-work block — it will appear in your chart and count toward the summary.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    startTimer()
                } label: {
                    Label("Start focus session", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("startFocusTimerButton")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            resumeTickerIfRunning()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func resumeTickerIfRunning() {
        guard isTimerRunning, let started = timerStartedAt else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(started))
        startTicker()
    }

    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.elapsedSeconds = Int(Date().timeIntervalSince(self.timerStartedAt ?? .now))
            }
        }
    }

    private func startTimer() {
        timerStartedAtRef = Date().timeIntervalSince1970
        elapsedSeconds = 0
        startTicker()
        if #available(iOS 16.1, *) {
            FocusLiveActivityManager.startLiveActivity()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        guard let started = timerStartedAt else { return }
        let ended = Date()
        timerStartedAtRef = 0
        let seconds = elapsedSeconds
        Task {
            if #available(iOS 16.1, *) {
                await FocusLiveActivityManager.endLiveActivity(elapsedSeconds: seconds)
            }
            await focus.createSession(taskID: nil, startedAt: started, endedAt: ended)
            await focus.loadFocus(after: range.dateStart, before: .now)
        }
    }

    private var summaryCard: some View {
        let minutes = (focus.summary?.totalDurationSeconds ?? 0) / 60
        let sessions = focus.summary?.sessionCount ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(minutes)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("minutes focused \(range.periodLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(sessions)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("sessions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Time focused by day")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(RangeOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            let days = dailyTotals(from: focus.dailySessions, days: range.days)
            Chart(days, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Minutes", day.minutes)
                )
                .foregroundStyle(.blue)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .frame(height: 160)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func analysisCard(_ analysis: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Focus insight", systemImage: "sparkles")
                .font(.headline)
            Text(analysis)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var reflectionButton: some View {
        Button {
            showingReflection = true
        } label: {
            Label("End-of-day reflection", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }

    private var reflectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reflections")
                .font(.headline)
            if focus.reflections.isEmpty {
                Text("No reflections yet. Take a moment each evening to review your focus.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(focus.reflections) { reflection in
                    ReflectionCard(reflection: reflection) { id in
                        Task { await focus.requestAnalysis(reflectionID: id) }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private struct DayTotal {
        let date: Date
        let minutes: Int
    }

    private func dailyTotals(from sessions: [FocusSession], days: Int) -> [DayTotal] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: .now) ?? .now)
        let today = calendar.startOfDay(for: .now)

        var totals: [DayTotal] = []
        var date = start
        while date <= today {
            let dayMinutes = sessions
                .filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
                .reduce(0) { $0 + $1.durationSeconds }
            totals.append(DayTotal(date: date, minutes: dayMinutes / 60))
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return totals
    }

}
