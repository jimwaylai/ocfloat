import AppKit

/// What summons Quick Chat: a double tap of ⌥ (the default) or a regular key combination.
enum HotkeyTrigger: Equatable, Codable, Sendable {
    case doubleTapOption
    case combo(Hotkey)

    static let `default` = HotkeyTrigger.doubleTapOption

    var displayString: String {
        switch self {
        case .doubleTapOption: String(localized: "Double-tap ⌥")
        case .combo(let hotkey): hotkey.displayString
        }
    }
}

/// Recognizes ⌥ pressed twice on its own, from the modifier state of successive
/// flags-changed events. Fires on the second press, so the panel appears without waiting
/// for the release. Holding ⌥ or combining it with other modifiers or keys does not count.
struct DoubleTapDetector {
    static let maximumTapDuration: TimeInterval = 0.3
    static let maximumGap: TimeInterval = 0.4

    private enum Phase {
        case idle
        case firstDown(at: TimeInterval)
        case firstUp(at: TimeInterval)
        /// Fired; waits for ⌥ to be released before a new sequence can start.
        case fired
    }

    private static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
    private var phase = Phase.idle

    /// Returns `true` when this change completes a double tap.
    mutating func handle(_ flags: NSEvent.ModifierFlags, at time: TimeInterval) -> Bool {
        let pressed = flags.intersection(Self.relevant)
        let optionOnly = pressed == .option
        switch phase {
        case .idle:
            if optionOnly { phase = .firstDown(at: time) }
        case .firstDown(let down):
            if pressed.isEmpty, time - down <= Self.maximumTapDuration {
                phase = .firstUp(at: time)
            } else if !optionOnly {
                phase = .idle
            }
        case .firstUp(let up):
            if optionOnly, time - up <= Self.maximumGap {
                phase = .fired
                return true
            }
            phase = optionOnly ? .firstDown(at: time) : .idle
        case .fired:
            if pressed.isEmpty { phase = .idle }
        }
        return false
    }

    /// A regular key was pressed, e.g. ⌥E to type an accent: the taps were not on their own.
    mutating func interrupt() {
        if case .fired = phase { return }
        phase = .idle
    }
}
