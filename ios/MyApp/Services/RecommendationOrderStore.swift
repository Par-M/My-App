import Foundation

/// Persists a manual ordering of item IDs so the user can drag to
/// prioritize / interleave recommended parts and fixed-event tasks on the
/// Schedule tab. Purely on-device (UserDefaults); the backend ordering is
/// unaffected. IDs are strings so a single part of a multi-part task can be
/// ordered independently from its siblings.
struct RecommendationOrderStore {
    private let defaults: UserDefaults
    private static let storageKey = "recommendation_order_ids"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Move `dragged` to sit immediately before `target` in the saved order.
    func move(_ dragged: String, before target: String) {
        var ids = self.ids
        ids.removeAll { $0 == dragged }
        if let index = ids.firstIndex(of: target) {
            ids.insert(dragged, at: index)
        } else {
            ids.append(dragged)
        }
        defaults.set(ids, forKey: Self.storageKey)
    }

    /// Sort `items` so manually-ordered IDs come first (in saved order),
    /// with everything else keeping its original position.
    func reorder<T>(_ items: [T], id keyPath: KeyPath<T, String>) -> [T] {
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

    private var ids: [String] {
        defaults.stringArray(forKey: Self.storageKey) ?? []
    }
}
