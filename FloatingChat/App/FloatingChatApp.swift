import SwiftUI

@main
struct FloatingChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ocfloat", image: "MenuBarIcon") {
            MenuBarMenu(appDelegate: appDelegate)
        }

        Settings {
            SettingsView(appDelegate: appDelegate)
        }
    }
}
