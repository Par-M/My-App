import SwiftUI

struct WeeklyScheduleView: View {
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(CalendarService.self) private var calendarService

    private enum ScheduleViewMode: String, CaseIterable, Identifiable {
        case day
        case week
        case month

        var id: String { rawValue }

        var label: String {
            switch self {
            case .day: "Day"
            case .week: "Week"
            case .month: "Month"
            }
        }
    }

    private var calendar: Calendar { Calendar.current }

    @State private var viewMode: ScheduleViewMode = .day
    @State private var selectedDate = Date()
    @State private var showProposal = false
    @State private var editingBlock: CalendarBlock?
    @State private var showPreferences = false
    @State private var busyEvents: [CalendarEventItem] = []
    @State private var errorDismissed = false

    private var dayStart: Date {
        calendar.startOfDay(for: selectedDate)
    }

    private var dayEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: dayStart) ?? selectedDate
    }

    private var weekDays: [Date] {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private var weekStart: Date {
        weekDays.first ?? Date()
    }

    private var weekEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: weekDays.last ?? weekStart) ?? weekStart
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
    }

    private var monthEnd: Date {
        calendar.date(byAdding: .month, value: 1, to: monthStart) ?? selectedDate
    }

    private var visibleStart: Date {
        switch viewMode {
        case .day: return dayStart
        case .week: return weekStart
        case .month: return monthStart
        }
    }

    private var visibleEnd: Date {
        switch viewMode {
        case .day: return dayEnd
        case .week: return weekEnd
        case .month: return monthEnd
        }
    }

    private var monthCells: [Date?] {
        let firstWeekday = calendar.firstWeekday
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (weekday - firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        cells.append(contentsOf: days.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: monthStart)
        })
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    viewModePicker
                    navigator

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

                    switch viewMode {
                    case .day:
                        dayContent
                    case .week:
                        ForEach(weekDays, id: \.self) { day in
                            daySection(day)
                        }
                    case .month:
                        monthGrid
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
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        selectedDate = Date()
                        viewMode = .day
                    } label: {
                        Label("Today", systemImage: "sun.max")
                    }
                    Spacer()
                }
            }
            .task(id: visibleStart) {
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

    private var viewModePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(ScheduleViewMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
    }

    private var navigator: some View {
        HStack {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous")

            Spacer()

            Text(navigatorTitle)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next")
        }
    }

    private var navigatorTitle: String {
        switch viewMode {
        case .day:
            if calendar.isDateInToday(selectedDate) {
                return "Today"
            }
            return selectedDate.formatted(
                .dateTime.weekday(.wide).month(.abbreviated).day()
            )
        case .week:
            return "Week of \(weekStart.formatted(date: .abbreviated, time: .omitted))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private func step(_ delta: Int) {
        switch viewMode {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: delta, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: delta, to: selectedDate) ?? selectedDate
        }
    }

    private var dayContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if calendar.isDateInToday(selectedDate) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text("Now · \(context.date.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            daySection(selectedDate)
        }
    }

    private var monthGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        monthCell(day)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func monthCell(_ day: Date) -> some View {
        let hasContent = scheduleService.blocks.contains {
            calendar.isDate($0.startAt, inSameDayAs: day)
        } || busyEvents.contains { calendar.isDate($0.start, inSameDayAs: day) }
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)

        return Button {
            selectedDate = day
            viewMode = .day
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .regular)
                Circle()
                    .fill(hasContent ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                isSelected ? Color.accentColor.opacity(0.2) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: isToday ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
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
        let ignored = calendarService.isIgnored(event)
        return Button {
            calendarService.toggleIgnored(event)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .strikethrough(ignored)
                    Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if ignored {
                    Image(systemName: "nosign")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ignore")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                (ignored ? Color.secondary.opacity(0.12) : Color(UIColor.quaternarySystemFill)),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
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
        busyEvents = calendarService.fetchEvents(from: visibleStart, to: visibleEnd)
    }

    private func generate() async {
        errorDismissed = false
        let ourEventIds = Set(scheduleService.blocks.compactMap { $0.calendarEventId })

        var busy: [BusyTimeRequest] = []
        if calendarService.permission == .granted {
            busyEvents = calendarService.fetchEvents(from: visibleStart, to: visibleEnd)
            busy.append(contentsOf: busyEvents
                .filter {
                    !ourEventIds.contains($0.id)
                        && !$0.isAllDay
                        && !calendarService.isIgnored($0)
                }
                .map { BusyTimeRequest(start: $0.start, end: $0.end) })
        }
        busy.append(contentsOf: scheduleService.blocks
            .filter { $0.startAt < visibleEnd && $0.endAt > visibleStart }
            .map { BusyTimeRequest(start: $0.startAt, end: $0.endAt) })

        await scheduleService.generate(startDate: visibleStart, endDate: visibleEnd, busyTimes: busy)
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
