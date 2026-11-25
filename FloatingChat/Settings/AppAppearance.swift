import AppKit

/// Light, dark, or following the system, for the panel and every other window.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "appearance"

    var id: String { rawValue }

    static func current(defaults: UserDefaults = .standard) -> AppAppearance {
        defaults.string(forKey: key).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    @MainActor
    static func apply(_ appearance: AppAppearance) {
        NSApp.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
