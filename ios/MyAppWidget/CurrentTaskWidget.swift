import WidgetKit
import SwiftUI

struct CurrentTaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentTaskEntry {
        CurrentTaskEntry(date: Date(), title: "Write report", taskEnd: Date().addingTimeInterval(3600), tasksRemaining: 3, workEndDate: Date().addingTimeInterval(28800), noTask: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentTaskEntry) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            title: data.title,
            taskEnd: data.taskEnd,
            tasksRemaining: data.tasksRemaining,
            workEndDate: data.workEndDate,
            noTask: data.noTask
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentTaskEntry>) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            title: data.title,
            taskEnd: data.taskEnd,
            tasksRemaining: data.tasksRemaining,
            workEndDate: data.workEndDate,
            noTask: data.noTask
        )

        var refreshDate = Date().addingTimeInterval(60)
        if let taskEnd = data.taskEnd, taskEnd > Date() && taskEnd < refreshDate {
            refreshDate = taskEnd
        } else if let workEnd = data.workEndDate, workEnd > Date() && workEnd < refreshDate {
            refreshDate = workEnd
        }

        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct CurrentTaskEntry: TimelineEntry {
    let date: Date
    let title: String?
    let taskEnd: Date?
    let tasksRemaining: Int
    let workEndDate: Date?
    let noTask: Bool
}

struct CurrentTaskWidget: Widget {
    let kind = "CurrentTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrentTaskProvider()) { entry in
            CurrentTaskWidgetView(entry: entry)
        }
        .configurationDisplayName("Current Task")
        .description("Shows what you're working on now.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    CurrentTaskWidget()
} timeline: {
    CurrentTaskEntry(date: .now, title: "Write report", taskEnd: Date().addingTimeInterval(5400), tasksRemaining: 3, workEndDate: Date().addingTimeInterval(28800), noTask: false)
}
