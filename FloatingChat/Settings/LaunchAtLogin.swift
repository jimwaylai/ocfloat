import Foundation
import Observation
import ServiceManagement
import os

/// Launch at login through the system's login items. On by default: it is turned on once,
/// at first launch, and from then on only the user changes it.
@MainActor
@Observable
final class LaunchAtLogin {
    private static let initializedKey = "launchAtLoginInitialized"

    private(set) var status = SMAppService.mainApp.status

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// The user turned it off in System Settings → Login Items, or has to allow it there.
    var requiresApproval: Bool { status == .requiresApproval }

    func enableOnFirstLaunch() {
        guard !defaults.bool(forKey: Self.initializedKey) else { return }
        defaults.set(true, forKey: Self.initializedKey)
        setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.app.error("Changing launch at login failed: \(error)")
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
