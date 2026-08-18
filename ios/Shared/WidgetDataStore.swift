import Foundation

struct WidgetDataStore {
    static let appGroupID = "group.com.AM29.MyApp"

    private static var shared: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(
        taskTitle: String?,
        taskEnd: Date?,
        workEndDate: Date?,
        habitsDone: Int,
        habitsTotal: Int
    ) {
        guard let defaults = shared else { return }

        if let title = taskTitle {
            defaults.set(title, forKey: "task_title")
        } else {
            defaults.removeObject(forKey: "task_title")
        }
        if let end = taskEnd {
            defaults.set(end.timeIntervalSince1970, forKey: "task_end_interval")
        } else {
            defaults.removeObject(forKey: "task_end_interval")
        }
        if let workEnd = workEndDate {
            defaults.set(workEnd.timeIntervalSince1970, forKey: "work_end_interval")
        }
        defaults.set(habitsDone, forKey: "habits_done")
        defaults.set(habitsTotal, forKey: "habits_total")
        defaults.set(Date().timeIntervalSince1970, forKey: "last_updated")
    }

    static func read() -> WidgetData {
        guard let defaults = shared else {
            return WidgetData(taskTitle: nil, taskEnd: nil, workEndDate: nil, habitsDone: 0, habitsTotal: 0)
        }
        let title = defaults.string(forKey: "task_title")
        let taskEndI = defaults.double(forKey: "task_end_interval")
        let taskEnd: Date? = taskEndI > 0 ? Date(timeIntervalSince1970: taskEndI) : nil
        let workEndI = defaults.double(forKey: "work_end_interval")
        let workEnd: Date? = workEndI > 0 ? Date(timeIntervalSince1970: workEndI) : nil
        let done = defaults.integer(forKey: "habits_done")
        let total = defaults.integer(forKey: "habits_total")
        return WidgetData(taskTitle: title, taskEnd: taskEnd, workEndDate: workEnd, habitsDone: done, habitsTotal: total)
    }
}

struct WidgetData {
    let taskTitle: String?
    let taskEnd: Date?
    let workEndDate: Date?
    let habitsDone: Int
    let habitsTotal: Int
}
