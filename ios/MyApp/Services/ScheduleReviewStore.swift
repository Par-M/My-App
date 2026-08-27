import Foundation

/// Tracks which fixed-event tasks the user has reviewed on the Schedule
/// tab's Review screen. Purely local — nothing here writes to Apple
/// Calendar. The key includes the task's updated_at so any edit sends it
/// back for re-review.
struct ScheduleReviewStore {
    private let defaults: UserDefaults
    private static let storageKey = "schedule_review_confirmed_keys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isConfirmed(_ task: TaskItem) -> Bool {
        confirmedKeys.contains(reviewKey(for: task))
    }

    func confirm(_ task: TaskItem) {
        var keys = confirmedKeys
        keys.insert(reviewKey(for: task))
        defaults.set(Array(keys), forKey: Self.storageKey)
    }

    func unconfirm(_ task: TaskItem) {
        var keys = confirmedKeys
        keys.remove(reviewKey(for: task))
        defaults.set(Array(keys), forKey: Self.storageKey)
    }

    func key(for task: TaskItem) -> String {
        reviewKey(for: task)
    }

    private func reviewKey(for task: TaskItem) -> String {
        "\(task.id.uuidString)-\(Int(task.updatedAt.timeIntervalSince1970))"
    }

    private var confirmedKeys: Set<String> {
        Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }
}
