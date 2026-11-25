import SwiftUI

struct MenuBarMenu: View {
    let appDelegate: AppDelegate

    private var hotkeys: HotkeyController { appDelegate.hotkeyController }

    var body: some View {
        Button("Show Quick Chat") {
            appDelegate.panelController.show()
        }

        if hotkeys.isRegistered {
            Text("Shortcut: \(hotkeys.activeDisplayString)")
        } else {
            Text("Shortcut \(hotkeys.activeDisplayString) is used by another app")
        }
        if hotkeys.resolution?.isFallback == true, case .combo(let preferred) = hotkeys.trigger {
            Text("Spotlight is using \(preferred.displayString)")
        }

        Divider()

        switch appDelegate.connection.state {
        case .connected:
            Text("opencode: Connected")
        case .connecting:
            Text("opencode: Connecting…")
        case .serviceNotRunning:
            Text("opencode service is not running")
            Button("Start opencode Service") {
                appDelegate.connection.startService()
            }
        case .opencodeNotFound:
            Text("opencode is not installed")
            Button("Check Again") {
                appDelegate.connection.retryNow()
            }
        case .invalidServerURL:
            Text("The server URL in Settings is not valid")
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        if appDelegate.updater.isAvailable {
            Button("Check for Updates…") {
                appDelegate.updater.checkForUpdates()
            }
            .disabled(!appDelegate.updater.canCheckForUpdates)
        }

        Divider()

        Button("Quit ocfloat") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
