import WidgetKit
import SwiftUI

struct TasksRemainingProvider: TimelineProvider {
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
        if let workEnd = data.workEndDate, workEnd > Date() && workEnd < refreshDate {
            refreshDate = workEnd
        }

        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct TasksRemainingWidget: Widget {
    let kind = "TasksRemainingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksRemainingProvider()) { entry in
            TasksRemainingWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasks Left")
        .description("Shows remaining tasks and time in your workday.")
        .supportedFamilies([.accessoryRectangular])
    }
}
