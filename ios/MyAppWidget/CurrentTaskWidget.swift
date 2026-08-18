import WidgetKit
import SwiftUI

struct CurrentTaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentTaskEntry {
        CurrentTaskEntry(date: Date(), title: "Write report", taskEnd: Date().addingTimeInterval(3600), habitsDone: 3, habitsTotal: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentTaskEntry) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            title: data.taskTitle,
            taskEnd: data.taskEnd,
            habitsDone: data.habitsDone,
            habitsTotal: data.habitsTotal
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentTaskEntry>) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            title: data.taskTitle,
            taskEnd: data.taskEnd,
            habitsDone: data.habitsDone,
            habitsTotal: data.habitsTotal
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
    let habitsDone: Int
    let habitsTotal: Int
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

struct TasksRemainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentTaskEntry {
        CurrentTaskEntry(date: Date(), title: "Write report", taskEnd: Date().addingTimeInterval(3600), habitsDone: 3, habitsTotal: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentTaskEntry) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            title: data.taskTitle,
            taskEnd: data.taskEnd,
            habitsDone: data.habitsDone,
            habitsTotal: data.habitsTotal
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentTaskEntry>) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            title: data.taskTitle,
            taskEnd: data.taskEnd,
            habitsDone: data.habitsDone,
            habitsTotal: data.habitsTotal
        )

        let refreshDate = Date().addingTimeInterval(60)
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
        .configurationDisplayName("Habits")
        .description("Shows today's habit progress.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    CurrentTaskWidget()
} timeline: {
    CurrentTaskEntry(date: .now, title: "Write report", taskEnd: Date().addingTimeInterval(5400), habitsDone: 3, habitsTotal: 5)
}

#Preview(as: .accessoryRectangular) {
    TasksRemainingWidget()
} timeline: {
    CurrentTaskEntry(date: .now, title: "Write report", taskEnd: Date().addingTimeInterval(5400), habitsDone: 3, habitsTotal: 5)
}
