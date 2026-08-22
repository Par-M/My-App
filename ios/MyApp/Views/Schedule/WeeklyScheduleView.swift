import SwiftUI

struct WeeklyScheduleView: View {
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(CalendarService.self) private var calendarService
    @Environment(RecommendationService.self) private var recommendationService
    @Environment(TaskService.self) private var taskService

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
    @State private var showPreferences = false
    @State private var busyEvents: [CalendarEventItem] = []
    @State private var errorDismissed = false
    @State private var expandedSlots: Set<String> = []

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

                    if recommendationService.isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Finding recommendations…")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }

                    if let message = activeErrorMessage, !errorDismissed {
                        errorBanner(message)
                    }

                    if calendarService.permission == .denied {
                        permissionDeniedBanner
                    }

                    switch viewMode {
                    case .day:
                        dayContent
                        unscheduledSection
                    case .week:
                        ForEach(weekDays, id: \.self) { day in
                            daySection(day)
                        }
                        unscheduledSection
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
                    NavigationLink {
                        CalendarSelectionView()
                    } label: {
                        Label("Calendars", systemImage: "calendar")
                    }
                }
            }
            .task(id: visibleStart) {
                await loadData()
            }
            .onChange(of: calendarService.permission) { _, newValue in
                if newValue == .granted {
                    Task { await loadData() }
                }
            }
            .sheet(isPresented: $showPreferences) {
                PreferencesView()
            }
        }
    }

    private var activeErrorMessage: String? {
        recommendationService.errorMessage ?? scheduleService.errorMessage
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
        let hasEvents = busyEvents.contains {
            calendar.isDate($0.start, inSameDayAs: day)
        }
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
                    .fill(hasEvents ? Color.accentColor : Color.clear)
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
            Text("Calendar access is off. Enable it in Settings to see your events.")
                .font(.footnote)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Day section (calendar events + recommendations)

    private func daySection(_ day: Date) -> some View {
        let groups = groupExactOverlap(events(for: day))
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

            if groups.isEmpty {
                Text("No events")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { slotIndex, group in
                        if group.count == 1 {
                            eventRow(group[0])
                        } else {
                            eventSlot(group, day: day, slotIndex: slotIndex)
                        }
                    }
                }
            }

            recommendationsSection(day)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isToday ? Color.accentColor : Color(.separator), lineWidth: isToday ? 1.5 : 0.5)
        )
    }

    // MARK: - Recommendations

    private func recommendationsSection(_ day: Date) -> some View {
        let recommendation = recommendationService.recommendations(for: day)

        return Group {
            if let recommendation {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text("Recommended")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(formatMinutes(recommendation.availableMinutes)) free")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    if recommendation.items.isEmpty {
                        Text("Nothing recommended — no free time or no open tasks.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(recommendation.items) { item in
                            recommendedRow(item)
                        }
                    }
                }
            } else if !recommendationService.isLoading,
                      let message = recommendationService.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func recommendedRow(_ item: RecommendedPart) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor(item.priority))
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(item))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if !item.reason.isEmpty {
                    Text(item.reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if item.isOverdue {
                    Label("Overdue", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let timeRange = recommendedTimeRange(item) {
                    Text(timeRange)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Text(formatMinutes(item.minutes))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func recommendedTimeRange(_ item: RecommendedPart) -> String? {
        guard let start = item.recommendedStart else { return nil }
        let end = item.recommendedEnd ?? start
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    private var unscheduledSection: some View {
        let parts = recommendationService.unscheduled
        return Group {
            if !parts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text("Doesn't fit this window")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("These tasks need more free time than the selected window has. Extend work hours in Preferences or free up calendar time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(parts) { part in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(priorityColor(part.priority))
                                .frame(width: 4, height: 22)
                            Text(displayTitle(taskTitle: part.taskTitle, partTitle: part.partTitle))
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer()
                            Text(formatMinutes(part.minutes))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            Color.orange.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
            }
        }
    }

    private func displayTitle(_ item: RecommendedPart) -> String {
        displayTitle(taskTitle: item.taskTitle, partTitle: item.partTitle)
    }

    private func displayTitle(taskTitle: String, partTitle: String?) -> String {
        guard let partTitle else { return taskTitle }
        if partTitle == taskTitle || partTitle.hasPrefix(taskTitle) {
            return partTitle
        }
        return "\(taskTitle) — \(partTitle)"
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: .red
        case .medium: .orange
        case .low: .gray
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }

    // MARK: - Events

    private func events(for day: Date) -> [CalendarEventItem] {
        busyEvents.filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    private func groupExactOverlap(_ items: [CalendarEventItem]) -> [[CalendarEventItem]] {
        let sorted = items.sorted { $0.start < $1.start }
        var groups: [[CalendarEventItem]] = []
        for item in sorted {
            var merged = false
            for i in groups.indices {
                if groups[i].contains(where: { $0.start == item.start && $0.end == item.end }) {
                    groups[i].append(item)
                    merged = true
                    break
                }
            }
            if !merged {
                groups.append([item])
            }
        }
        return groups
    }

    private func slotKey(_ day: Date, slotIndex: Int) -> String {
        "\(Int(day.timeIntervalSince1970))_\(slotIndex)"
    }

    private func eventSlot(_ items: [CalendarEventItem], day: Date, slotIndex: Int) -> some View {
        let key = slotKey(day, slotIndex: slotIndex)
        let isExpanded = expandedSlots.contains(key)

        return VStack(spacing: 0) {
            if isExpanded {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 {
                        Divider().padding(.horizontal, 8)
                    }
                    eventRow(item)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        _ = expandedSlots.remove(key)
                    }
                } label: {
                    Label("Collapse", systemImage: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            } else {
                let first = items[0]
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        _ = expandedSlots.insert(key)
                    }
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.gray)
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(first.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(first.start.formatted(date: .omitted, time: .shortened)) – \(first.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(items.count - 1) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(
                        Color(UIColor.quaternarySystemFill),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
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

    // MARK: - Data loading

    private func loadData() async {
        errorDismissed = false
        await scheduleService.loadPreferences()

        guard await calendarService.requestPermission() == .granted else {
            busyEvents = []
            return
        }

        busyEvents = calendarService.fetchEvents(from: visibleStart, to: visibleEnd)

        await recommendationService.load(
            from: visibleStart,
            to: visibleEnd,
            excluding: Set(busyEvents.filter { calendarService.isIgnored($0) }.map(\.id))
        )
    }
}

#Preview {
    WeeklyScheduleView()
        .environment(ScheduleService())
        .environment(CalendarService())
        .environment(TaskService())
        .environment(RecommendationService())
}
