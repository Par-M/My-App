import AppIntents
import WidgetKit

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
struct CompleteTopTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Top Task"
    static var description = IntentDescription("Marks the top priority task as completed.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let current = WidgetDataStore.read()
        var updatedTitles = current.topTaskTitles
        if !updatedTitles.isEmpty {
            updatedTitles.removeFirst()
        }
        let updatedTaskCount = max(0, current.tasksRemaining - 1)
        
        WidgetDataStore.write(
            currentTaskTitle: updatedTitles.first,
            nextTaskTitle: updatedTitles.dropFirst().first,
            tasksRemaining: updatedTaskCount,
            habitsRemaining: current.habitsRemaining,
            topTaskTitles: updatedTitles,
            habitTitles: current.habitTitles
        )
        
        WidgetCenter.shared.reloadTimelines(ofKind: "CurrentTaskWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "TasksRemainingWidget")
        
        return .result()
    }
}
