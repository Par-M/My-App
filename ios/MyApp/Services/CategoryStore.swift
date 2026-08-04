import Foundation
import Observation

@MainActor
@Observable
final class CategoryStore {
    private static let key = "app.categories"

    private(set) var storedCategories: [String] {
        didSet {
            UserDefaults.standard.set(storedCategories, forKey: Self.key)
        }
    }

    init() {
        storedCategories = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func add(_ category: String) {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !storedCategories.contains(trimmed) else { return }
        storedCategories.append(trimmed)
    }

    func remove(_ category: String) {
        storedCategories.removeAll { $0 == category }
    }

    func categories(from tasks: [TaskItem]) -> [String] {
        let fromTasks = tasks.compactMap(\.category)
        var all = storedCategories
        for category in fromTasks where !all.contains(category) {
            all.append(category)
        }
        return all.sorted()
    }
}
