import Foundation

/// Persists a manual ordering of task IDs so the user can drag to
/// prioritize recommended/fixed-event items on the Schedule tab. Purely
/// on-device (UserDefaults); the backend ordering is unaffected.
struct RecommendationOrderStore {
    private let defaults: UserDefaults
    private static let storageKey = "recommendation_order_ids"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Move `dragged` to sit immediately before `target` in the saved order.
    func move(_ dragged: UUID, before target: UUID) {
        var ids = self.ids
        ids.removeAll { $0 == dragged }
        if let index = ids.firstIndex(of: target) {
            ids.insert(dragged, at: index)
        } else {
            ids.append(dragged)
        }
        defaults.set(ids.map(\.uuidString), forKey: Self.storageKey)
    }

    /// Sort `items` so manually-ordered IDs come first (in saved order),
    /// with everything else keeping its original position.
    func reorder<T>(_ items: [T], id keyPath: KeyPath<T, UUID>) -> [T] {
        let rank = Dictionary(
            uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) }
        )
        return items
            .enumerated()
            .sorted { a, b in
                let ra = rank[a.element[keyPath: keyPath]]
                let rb = rank[b.element[keyPath: keyPath]]
                switch (ra, rb) {
                case (.some(let x), .some(let y)): return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.offset < b.offset
                }
            }
            .map { $0.element }
    }

    private var ids: [UUID] {
        (defaults.stringArray(forKey: Self.storageKey) ?? [])
            .compactMap { UUID(uuidString: $0) }
    }
}
