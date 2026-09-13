import Charts
import SwiftUI

extension Notification.Name {
    static let openReflection = Notification.Name("openReflection")
}

struct FocusDashboardView: View {
    @Environment(FocusService.self) private var focus

    private enum RangeOption: String, CaseIterable, Identifiable {
        case week = "1W"
        case twoWeeks = "2W"
        case month = "4W"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 28
            }
        }
        var dateStart: Date {
            Calendar.current.date(byAdding: .day, value: -(days - 1), to: .now) ?? .now
        }
    }

    @State private var range: RangeOption = .week
    @State private var showingReflection = false

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
                        Task { await focus.loadFocus() }
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
                await focus.loadFocus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openReflection)) { _ in
                showingReflection = true
            }
        }
    }

    private var summaryCard: some View {
        let minutes = (focus.summary?.totalDurationSeconds ?? 0) / 60
        let sessions = focus.summary?.sessionCount ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(minutes)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("minutes focused this period")
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
                .frame(width: 150)
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
