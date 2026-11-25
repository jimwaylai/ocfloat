import AppKit

/// The interface language. It is applied through the app's own `AppleLanguages` default,
/// which macOS reads only at launch, so a change needs a restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case traditionalChinese

    private static let key = "AppleLanguages"

    var id: String { rawValue }

    /// The localization this language forces; `nil` follows the system's language order.
    var localization: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .traditionalChinese: "zh-Hant"
        }
    }

    /// Reads only the app's domain: `UserDefaults.object(forKey:)` would also return the
    /// system-wide `AppleLanguages`.
    static func current(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "") -> AppLanguage {
        let languages = defaults.persistentDomain(forName: domain)?[key] as? [String]
        return allCases.first { $0.localization != nil && $0.localization == languages?.first } ?? .system
    }

    static func set(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        if let localization = language.localization {
            defaults.set([localization], forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// The language the running app was launched with.
    static let atLaunch = current()

    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundleURL.path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Waits for this instance to quit, so `open` starts a new one instead of activating it.
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
