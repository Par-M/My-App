import WidgetKit
import SwiftUI

struct CurrentTaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentTaskEntry {
        CurrentTaskEntry(
            date: Date(),
            topTaskTitles: ["Finish pitch deck", "Review PRs", "Email landlord"],
            habitTitles: ["Morning run", "Read 30 min"],
            tasksRemaining: 4,
            habitsRemaining: 2
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentTaskEntry) -> Void) {
        let data = WidgetDataStore.read()
        completion(CurrentTaskEntry(
            date: Date(),
            topTaskTitles: data.topTaskTitles,
            habitTitles: data.habitTitles,
            tasksRemaining: data.tasksRemaining,
            habitsRemaining: data.habitsRemaining
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentTaskEntry>) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            topTaskTitles: data.topTaskTitles,
            habitTitles: data.habitTitles,
            tasksRemaining: data.tasksRemaining,
            habitsRemaining: data.habitsRemaining
        )
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
        completion(timeline)
    }
}

struct CurrentTaskEntry: TimelineEntry {
    let date: Date
    let topTaskTitles: [String]
    let habitTitles: [String]
    let tasksRemaining: Int
    let habitsRemaining: Int
}

struct CurrentTaskWidget: Widget {
    let kind = "CurrentTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrentTaskProvider()) { entry in
            CurrentTaskWidgetView(entry: entry)
        }
        .configurationDisplayName("Top Priority Today")
        .description("Shows your highest priority tasks to complete today.")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium, .systemLarge])
    }
}

struct TasksRemainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentTaskEntry {
        CurrentTaskEntry(date: Date(), topTaskTitles: [], habitTitles: ["Morning run"], tasksRemaining: 4, habitsRemaining: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentTaskEntry) -> Void) {
        let data = WidgetDataStore.read()
        completion(CurrentTaskEntry(
            date: Date(),
            topTaskTitles: data.topTaskTitles,
            habitTitles: data.habitTitles,
            tasksRemaining: data.tasksRemaining,
            habitsRemaining: data.habitsRemaining
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentTaskEntry>) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            topTaskTitles: data.topTaskTitles,
            habitTitles: data.habitTitles,
            tasksRemaining: data.tasksRemaining,
            habitsRemaining: data.habitsRemaining
        )
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
        completion(timeline)
    }
}

struct TasksRemainingWidget: Widget {
    let kind = "TasksRemainingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksRemainingProvider()) { entry in
            TasksRemainingWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasks & Habits")
        .description("Shows remaining tasks and habits.")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium, .systemLarge])
    }
}
