import Foundation
import WidgetKit

@MainActor
enum FocusTimerStarter {
    static let startedAtKey = "focusTimerStartedAt"
    static let activeTaskIDKey = "focusActiveTaskID"
    static let activeTaskTitleKey = "focusActiveTaskTitle"
    static let activeCategoryKey = "focusActiveCategory"

    static var activeTaskID: UUID? {
        guard let raw = UserDefaults.standard.string(forKey: activeTaskIDKey),
              let id = UUID(uuidString: raw) else { return nil }
        return id
    }

    static var activeTaskTitle: String? {
        let value = UserDefaults.standard.string(forKey: activeTaskTitleKey) ?? ""
        return value.isEmpty ? nil : value
    }

    static var activeCategory: String? {
        let value = UserDefaults.standard.string(forKey: activeCategoryKey) ?? ""
        return value.isEmpty ? nil : value
    }

    static var startedAt: TimeInterval {
        UserDefaults.standard.double(forKey: startedAtKey)
    }

    /// Starts the app-wide focus timer, optionally tied to a task so the logged
    /// session can be attributed to that task's category and remaining time.
    static func startFocus(
        taskID: UUID? = nil,
        title: String? = nil,
        category: String? = nil
    ) {
        let defaults = UserDefaults.standard
        let startedAt = Date().timeIntervalSince1970

        defaults.set(startedAt, forKey: startedAtKey)

        if let taskID {
            defaults.set(taskID.uuidString, forKey: activeTaskIDKey)
        } else {
            defaults.removeObject(forKey: activeTaskIDKey)
        }

        if let title, !title.isEmpty {
            defaults.set(title, forKey: activeTaskTitleKey)
        } else {
            defaults.removeObject(forKey: activeTaskTitleKey)
        }

        if let category, !category.isEmpty {
            defaults.set(category, forKey: activeCategoryKey)
        } else {
            defaults.removeObject(forKey: activeCategoryKey)
        }

        WidgetDataStore.writeFocus(startedAt: startedAt, title: title ?? "Deep Work Session")
        WidgetCenter.shared.reloadTimelines(ofKind: "FocusTimerWidget")

        if #available(iOS 16.1, *) {
            FocusLiveActivityManager.startLiveActivity()
        }
    }

    static func clearActiveTask() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: activeTaskIDKey)
        defaults.removeObject(forKey: activeTaskTitleKey)
        defaults.removeObject(forKey: activeCategoryKey)
    }
}