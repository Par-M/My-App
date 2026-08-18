import Foundation

struct WidgetDataStore {
    static let appGroupID = "group.com.AM29.MyApp"
    static let currentTaskKey = "widget_current_task"
    static let tasksRemainingKey = "widget_tasks_remaining"
    static let workEndDateKey = "widget_work_end_date"
    static let lastUpdatedKey = "widget_last_updated"
    static let noTaskKey = "widget_no_task"

    private static var shared: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(taskTitle: String?, taskEnd: Date?, tasksRemaining: Int, workEndDate: Date?) {
        guard let defaults = shared else { return }
        if let title = taskTitle {
            defaults.set(title, forKey: currentTaskKey)
            defaults.set(false, forKey: noTaskKey)
        } else {
            defaults.removeObject(forKey: currentTaskKey)
            defaults.set(true, forKey: noTaskKey)
        }
        if let end = taskEnd {
            defaults.set(end.timeIntervalSince1970, forKey: "widget_task_end_interval")
        } else {
            defaults.removeObject(forKey: "widget_task_end_interval")
        }
        defaults.set(tasksRemaining, forKey: tasksRemainingKey)
        if let workEnd = workEndDate {
            defaults.set(workEnd.timeIntervalSince1970, forKey: workEndDateKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: lastUpdatedKey)
    }

    static func clear() {
        guard let defaults = shared else { return }
        defaults.removeObject(forKey: currentTaskKey)
        defaults.removeObject(forKey: "widget_task_end_interval")
        defaults.removeObject(forKey: tasksRemainingKey)
        defaults.removeObject(forKey: workEndDateKey)
        defaults.removeObject(forKey: lastUpdatedKey)
        defaults.removeObject(forKey: noTaskKey)
    }

    static func read() -> (title: String?, taskEnd: Date?, tasksRemaining: Int, workEndDate: Date?, noTask: Bool) {
        guard let defaults = shared else {
            return (nil, nil, 0, nil, true)
        }
        let title = defaults.string(forKey: currentTaskKey)
        let taskEndInterval = defaults.double(forKey: "widget_task_end_interval")
        let taskEnd: Date? = taskEndInterval > 0 ? Date(timeIntervalSince1970: taskEndInterval) : nil
        let tasksRemaining = defaults.integer(forKey: tasksRemainingKey)
        let workEndInterval = defaults.double(forKey: workEndDateKey)
        let workEnd: Date? = workEndInterval > 0 ? Date(timeIntervalSince1970: workEndInterval) : nil
        let noTask = defaults.bool(forKey: noTaskKey)
        return (title, taskEnd, tasksRemaining, workEnd, noTask)
    }
}
