import SwiftUI

struct WeeklyScheduleView: View {
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(CalendarService.self) private var calendarService

    @State private var selectedDate = Date()
    @State private var showProposal = false
    @State private var editingBlock: CalendarBlock?
    @State private var showPreferences = false
    @State private var busyEvents: [CalendarEventItem] = []
    @State private var errorDismissed = false

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private var weekStart: Date {
        weekDays.first ?? Date()
    }

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: weekDays.last ?? weekStart) ?? weekStart
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekNavigator

                    if scheduleService.isGenerating {
                        HStack {
                            Spacer()
                            ProgressView("Generating schedule…")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }

                    if let errorMessage = scheduleService.errorMessage, !errorDismissed {
                        errorBanner(errorMessage)
                    }

                    if calendarService.permission == .denied {
                        permissionDeniedBanner
                    }

                    ForEach(weekDays, id: \.self) { day in
                        daySection(day)
                    }
                }
                .padding()
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await generate() }
                    } label: {
                        Label("Generate Schedule", systemImage: "wand.and.stars")
                    }
                    .disabled(scheduleService.isGenerating)

                    Button {
                        showPreferences = true
                    } label: {
                        Label("Preferences", systemImage: "gearshape")
                    }

                    Button {
                        Task { await loadData() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .task(id: weekStart) {
                await loadData()
            }
            .sheet(isPresented: $showProposal) {
                ScheduleProposalView()
            }
            .sheet(item: $editingBlock) { block in
                BlockTimeEditorView(block: block)
            }
            .sheet(isPresented: $showPreferences) {
                PreferencesView()
            }
        }
    }

    private var weekNavigator: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous week")

            Spacer()

            Text("Week of \(weekStart.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next week")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Text(message)
                .font(.footnote)
            Spacer()
            Button {
                errorDismissed = true
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var permissionDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
            Text("Calendar access is off. Enable it in Settings to find free time.")
                .font(.footnote)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private func daySection(_ day: Date) -> some View {
        let calendar = Calendar.current
        let dayBlocks = scheduleService.blocks
            .filter { calendar.isDate($0.startAt, inSameDayAs: day) }
            .sorted { $0.startAt < $1.startAt }
        let dayEvents = busyEvents
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
        let isToday = calendar.isDateInToday(day)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(day, format: .dateTime.weekday(.abbreviated))
                    .font(.headline)
                Text(day, format: .dateTime.month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if isToday {
                    Text("Today")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                }
            }

            if dayEvents.isEmpty && dayBlocks.isEmpty {
                Text("No events")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 6) {
                    ForEach(dayEvents) { event in
                        eventRow(event)
                    }
                    ForEach(dayBlocks) { block in
                        blockRow(block)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isToday ? Color.accentColor : Color(.separator), lineWidth: isToday ? 1.5 : 0.5)
        )
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.gray)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func blockRow(_ block: CalendarBlock) -> some View {
        Button {
            editingBlock = block
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("\(block.startAt.formatted(date: .omitted, time: .shortened)) – \(block.endAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func loadData() async {
        await scheduleService.loadBlocks()
        await scheduleService.loadPreferences()
        guard await calendarService.requestPermission() == .granted else {
            busyEvents = []
            return
        }
        busyEvents = calendarService.fetchEvents(from: weekStart, to: weekEnd)
    }

    private func generate() async {
        errorDismissed = false
        let ourEventIds = Set(scheduleService.blocks.compactMap { $0.calendarEventId })

        var busy: [BusyTimeRequest] = []
        if calendarService.permission == .granted {
            busyEvents = calendarService.fetchEvents(from: weekStart, to: weekEnd)
            busy.append(contentsOf: busyEvents
                .filter { !ourEventIds.contains($0.id) && !$0.isAllDay }
                .map { BusyTimeRequest(start: $0.start, end: $0.end) })
        }
        busy.append(contentsOf: scheduleService.blocks
            .filter { $0.startAt < weekEnd && $0.endAt > weekStart }
            .map { BusyTimeRequest(start: $0.startAt, end: $0.endAt) })

        await scheduleService.generate(startDate: weekStart, endDate: weekEnd, busyTimes: busy)
        if scheduleService.proposal != nil {
            showProposal = true
        }
    }
}

#Preview {
    WeeklyScheduleView()
        .environment(ScheduleService())
        .environment(CalendarService())
}
