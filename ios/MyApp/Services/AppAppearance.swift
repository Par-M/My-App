import Foundation
import Observation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
@Observable
final class AppearanceSettings {
    private static let key = "app.theme"

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
        }
    }

    init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "")
            ?? .system
    }
}
