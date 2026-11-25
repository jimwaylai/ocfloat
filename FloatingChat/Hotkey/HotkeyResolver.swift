struct HotkeyResolution: Equatable, Sendable {
    let active: Hotkey
    /// True when the preferred hotkey is held by Spotlight and the fallback is in use.
    let isFallback: Bool
}

enum HotkeyResolver {
    static func resolve(preferred: Hotkey, spotlight: Hotkey?, fallback: Hotkey = .optionSpace) -> HotkeyResolution {
        preferred == spotlight
            ? HotkeyResolution(active: fallback, isFallback: true)
            : HotkeyResolution(active: preferred, isFallback: false)
    }
}
