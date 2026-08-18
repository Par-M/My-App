import Foundation

struct WidgetDataStore {
    static let appGroupID = "group.com.AM29.MyApp"

    private static var shared: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(
        currentTaskTitle: String?,
        nextTaskTitle: String?,
        tasksRemaining: Int,
        habitsRemaining: Int
    ) {
        guard let defaults = shared else { return }

        if let title = currentTaskTitle {
            defaults.set(title, forKey: "current_task_title")
        } else {
            defaults.removeObject(forKey: "current_task_title")
        }
        if let next = nextTaskTitle {
            defaults.set(next, forKey: "next_task_title")
        } else {
            defaults.removeObject(forKey: "next_task_title")
        }
        defaults.set(tasksRemaining, forKey: "tasks_remaining")
        defaults.set(habitsRemaining, forKey: "habits_remaining")
        defaults.set(Date().timeIntervalSince1970, forKey: "last_updated")
    }

    static func read() -> WidgetData {
        guard let defaults = shared else {
            return WidgetData(currentTaskTitle: nil, nextTaskTitle: nil, tasksRemaining: 0, habitsRemaining: 0)
        }
        return WidgetData(
            currentTaskTitle: defaults.string(forKey: "current_task_title"),
            nextTaskTitle: defaults.string(forKey: "next_task_title"),
            tasksRemaining: defaults.integer(forKey: "tasks_remaining"),
            habitsRemaining: defaults.integer(forKey: "habits_remaining")
        )
    }
}

struct WidgetData {
    let currentTaskTitle: String?
    let nextTaskTitle: String?
    let tasksRemaining: Int
    let habitsRemaining: Int
}
