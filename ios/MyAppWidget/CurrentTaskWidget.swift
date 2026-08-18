import WidgetKit
import SwiftUI

struct CurrentTaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentTaskEntry {
        CurrentTaskEntry(date: Date(), currentTaskTitle: "Write report", nextTaskTitle: "Review PRs", tasksRemaining: 4, habitsRemaining: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentTaskEntry) -> Void) {
        let data = WidgetDataStore.read()
        completion(CurrentTaskEntry(
            date: Date(),
            currentTaskTitle: data.currentTaskTitle,
            nextTaskTitle: data.nextTaskTitle,
            tasksRemaining: data.tasksRemaining,
            habitsRemaining: data.habitsRemaining
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentTaskEntry>) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            currentTaskTitle: data.currentTaskTitle,
            nextTaskTitle: data.nextTaskTitle,
            tasksRemaining: data.tasksRemaining,
            habitsRemaining: data.habitsRemaining
        )
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
        completion(timeline)
    }
}

struct CurrentTaskEntry: TimelineEntry {
    let date: Date
    let currentTaskTitle: String?
    let nextTaskTitle: String?
    let tasksRemaining: Int
    let habitsRemaining: Int
}

struct CurrentTaskWidget: Widget {
    let kind = "CurrentTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrentTaskProvider()) { entry in
            CurrentTaskWidgetView(entry: entry)
        }
        .configurationDisplayName("Current Task")
        .description("Shows your current and next task.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct TasksRemainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentTaskEntry {
        CurrentTaskEntry(date: Date(), currentTaskTitle: "Write report", nextTaskTitle: "Review PRs", tasksRemaining: 4, habitsRemaining: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentTaskEntry) -> Void) {
        let data = WidgetDataStore.read()
        completion(CurrentTaskEntry(
            date: Date(),
            currentTaskTitle: data.currentTaskTitle,
            nextTaskTitle: data.nextTaskTitle,
            tasksRemaining: data.tasksRemaining,
            habitsRemaining: data.habitsRemaining
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentTaskEntry>) -> Void) {
        let data = WidgetDataStore.read()
        let entry = CurrentTaskEntry(
            date: Date(),
            currentTaskTitle: data.currentTaskTitle,
            nextTaskTitle: data.nextTaskTitle,
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
        .supportedFamilies([.accessoryRectangular])
    }
}
