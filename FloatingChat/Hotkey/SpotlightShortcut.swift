import Foundation

/// Reads which shortcut, if any, Spotlight currently claims. The system handles it before
/// any app, so registering the same combination silently never fires.
enum SpotlightShortcut {
    private static let domain = "com.apple.symbolichotkeys"
    private static let key = "AppleSymbolicHotKeys"
    private static let showSpotlightSearchID = "64"

    static func current() -> Hotkey? {
        CFPreferencesAppSynchronize(domain as CFString)
        let raw = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? [String: Any]
        return occupiedHotkey(in: raw)
    }

    /// `nil` means Spotlight's shortcut is disabled. A missing entry means macOS has never
    /// written one, so the default `⌘Space` applies.
    static func occupiedHotkey(in symbolicHotKeys: [String: Any]?) -> Hotkey? {
        guard let entry = symbolicHotKeys?[showSpotlightSearchID] as? [String: Any] else {
            return .commandSpace
        }
        guard (entry["enabled"] as? NSNumber)?.boolValue ?? true else { return nil }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber],
              parameters.count >= 3
        else { return .commandSpace }
        return Hotkey(keyCode: parameters[1].uint32Value, modifiers: parameters[2].uintValue)
    }
}
