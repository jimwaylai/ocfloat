import AppKit
import SwiftUI

/// Shown once, at first launch: how to summon Quick Chat, whether opencode is reachable,
/// and launch at login.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private static let completedKey = "onboardingCompleted"

    private let appDelegate: AppDelegate
    private let defaults: UserDefaults
    private var window: NSWindow?

    init(appDelegate: AppDelegate, defaults: UserDefaults = .standard) {
        self.appDelegate = appDelegate
        self.defaults = defaults
    }

    func showIfFirstLaunch() {
        guard !defaults.bool(forKey: Self.completedKey) else { return }
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(appDelegate: appDelegate) { [weak self] in
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Welcome")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        defaults.set(true, forKey: Self.completedKey)
    }
}

private struct OnboardingView: View {
    let appDelegate: AppDelegate
    let done: () -> Void

    private var hotkeys: HotkeyController { appDelegate.hotkeyController }
    private var connection: ConnectionManager { appDelegate.connection }
    private var launchAtLogin: LaunchAtLogin { appDelegate.launchAtLogin }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to ocfloat")
                        .font(.title2.weight(.semibold))
                    Text("Ask quick questions from anywhere, answered through opencode.")
                        .foregroundStyle(.secondary)
                }
            }

            step(number: 1, title: "Summon Quick Chat") {
                Text("Press \(hotkeys.activeDisplayString) in any app to show or hide Quick Chat. Try it now.")
                if hotkeys.pressCount > 0 {
                    Label("It works", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                HotkeyStatus(hotkeys: hotkeys)
                Text("You can change the shortcut in Settings.")
                    .foregroundStyle(.secondary)
            }

            step(number: 2, title: "Connect to opencode") {
                ConnectionStatus(connection: connection)
                switch connection.state {
                case .opencodeNotFound:
                    Text("Install opencode, then check again. If it is installed somewhere unusual, set its path in Settings → opencode.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Link("opencode.ai", destination: URL(string: "https://opencode.ai")!)
                        Button("Check Again", action: connection.retryNow)
                    }
                case .serviceNotRunning:
                    Button("Start opencode Service", action: connection.startService)
                case .invalidServerURL:
                    Text("Fix the server URL in Settings → opencode.")
                        .foregroundStyle(.secondary)
                case .connected, .connecting:
                    EmptyView()
                }
            }

            step(number: 3, title: "Always ready") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled))
                Text("Quick Chat lives in the menu bar, where you also find Settings.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .padding(.top, 8)
        .frame(width: 500)
        .onAppear(perform: launchAtLogin.refresh)
    }

    private func step(number: Int, title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: .circle)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                content()
            }
        }
    }
}
