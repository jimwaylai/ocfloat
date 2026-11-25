import Foundation
import Observation

@MainActor
@Observable
final class HotkeyController {
    private static let triggerKey = "hotkeyTrigger"
    /// The user can free Spotlight's shortcut in System Settings at any time; polling picks it up without a relaunch.
    private static let spotlightPollInterval: TimeInterval = 3

    private(set) var trigger: HotkeyTrigger
    /// For a key combination only: the one in use, which may be the fallback.
    private(set) var resolution: HotkeyResolution?
    private(set) var isRegistered = false
    /// Counts summons through the shortcut, so the first-launch guide can confirm it works.
    private(set) var pressCount = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registrar = GlobalHotkeyRegistrar.shared
    @ObservationIgnored private let doubleTap = ModifierDoubleTapMonitor()
    @ObservationIgnored private var onPress: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isSuspended = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        trigger = defaults.data(forKey: Self.triggerKey)
            .flatMap { try? JSONDecoder().decode(HotkeyTrigger.self, from: $0) } ?? .default
    }

    /// What summons the panel right now, for display.
    var activeDisplayString: String {
        if let resolution { return resolution.active.displayString }
        return trigger.displayString
    }

    func start(onPress: @escaping () -> Void) {
        self.onPress = onPress
        registrar.onPress = { [weak self] in self?.fire() }
        doubleTap.onDoubleTap = { [weak self] in self?.fire() }
        apply()
        timer = Timer.scheduledTimer(withTimeInterval: Self.spotlightPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSpotlight() }
        }
    }

    func setTrigger(_ trigger: HotkeyTrigger) {
        self.trigger = trigger
        defaults.set(try? JSONEncoder().encode(trigger), forKey: Self.triggerKey)
        apply()
    }

    /// While a new combination is being recorded, the current one must not fire or swallow keys.
    func suspend() {
        isSuspended = true
        registrar.unregister()
    }

    func resume() {
        isSuspended = false
        apply()
    }

    private func fire() {
        guard !isSuspended else { return }
        pressCount += 1
        onPress?()
    }

    private func apply() {
        switch trigger {
        case .doubleTapOption:
            registrar.unregister()
            resolution = nil
            doubleTap.start()
            isRegistered = true
        case .combo(let hotkey):
            doubleTap.stop()
            let next = HotkeyResolver.resolve(preferred: hotkey, spotlight: SpotlightShortcut.current())
            resolution = next
            isRegistered = isSuspended || registrar.register(next.active)
        }
    }

    private func refreshSpotlight() {
        guard case .combo(let hotkey) = trigger, !isSuspended else { return }
        let next = HotkeyResolver.resolve(preferred: hotkey, spotlight: SpotlightShortcut.current())
        guard next != resolution else { return }
        resolution = next
        isRegistered = registrar.register(next.active)
    }
}
