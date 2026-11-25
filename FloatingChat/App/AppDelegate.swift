import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkeyController = HotkeyController()
    let connection = ConnectionManager()
    let launchAtLogin = LaunchAtLogin()
    let updater = Updater()
    private(set) lazy var panelController = QuickChatPanelController(connection: connection)
    private lazy var onboarding = OnboardingWindowController(appDelegate: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = AppLanguage.atLaunch
        AppAppearance.apply(.current())
        hotkeyController.start { [weak self] in
            self?.panelController.toggle()
        }
        prepareWorkspace()
        connection.start()
        // Unit tests run inside the app; they must not touch login items or open windows.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        launchAtLogin.enableOnFirstLaunch()
        onboarding.showIfFirstLaunch()
    }

    private func prepareWorkspace() {
        do {
            try ScratchWorkspace.ensure()
            try QuickAgent.installIfMissing()
        } catch {
            Logger.app.error("Preparing the workspace failed: \(error)")
        }
    }
}
