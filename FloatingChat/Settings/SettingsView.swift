import AppKit
import SwiftUI

struct SettingsView: View {
    let appDelegate: AppDelegate

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(hotkeys: appDelegate.hotkeyController, launchAtLogin: appDelegate.launchAtLogin)
            }
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettings()
            }
            Tab("opencode", systemImage: "terminal") {
                OpenCodeSettings(connection: appDelegate.connection)
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettings(updater: appDelegate.updater)
            }
        }
        .frame(width: 520)
        .onAppear {
            NSApp.activate()
        }
    }
}

private struct GeneralSettings: View {
    let hotkeys: HotkeyController
    let launchAtLogin: LaunchAtLogin
    @AppStorage(IdleReset.minutesKey) private var idleResetMinutes = IdleReset.defaultMinutes
    @State private var language = AppLanguage.current()

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "繁體中文").tag(AppLanguage.traditionalChinese)
                }
                .onChange(of: language) { AppLanguage.set(language) }
                if language != AppLanguage.atLaunch {
                    LabeledContent {
                        Button("Restart Now", action: AppLanguage.relaunch)
                    } label: {
                        Text("Restart ocfloat to use the new language.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker("Shortcut", selection: Binding(get: { isCombo }, set: setCombo)) {
                    Text("Double-tap ⌥").tag(false)
                    Text("Key combination").tag(true)
                }
                if case .combo(let hotkey) = hotkeys.trigger {
                    LabeledContent("Key combination") {
                        HotkeyRecorder(hotkeys: hotkeys, current: hotkey)
                    }
                }
                HotkeyStatus(hotkeys: hotkeys)
            } footer: {
                Text("Summons and hides Quick Chat from any app.")
                    .settingsFooter()
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled))
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…", action: launchAtLogin.openSystemSettings)
                    } label: {
                        Text("Allow it in System Settings to launch at login.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Stepper(value: $idleResetMinutes, in: 1...240) {
                    LabeledContent("Start a new conversation after", value: String(localized: "\(idleResetMinutes) min idle"))
                }
            } footer: {
                Text("Checked only when you summon Quick Chat, and never while an answer is unread.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: launchAtLogin.refresh)
    }

    private var isCombo: Bool {
        if case .combo = hotkeys.trigger { true } else { false }
    }

    private func setCombo(_ combo: Bool) {
        guard combo != isCombo else { return }
        hotkeys.setTrigger(combo ? .combo(.optionSpace) : .doubleTapOption)
    }
}

/// Explains when the chosen shortcut cannot be used as is.
struct HotkeyStatus: View {
    let hotkeys: HotkeyController

    var body: some View {
        if let resolution = hotkeys.resolution, resolution.isFallback, case .combo(let preferred) = hotkeys.trigger {
            LabeledContent {
                Button("Open Keyboard Shortcuts…", action: SystemSettings.openKeyboardShortcuts)
            } label: {
                Text("Spotlight is using \(preferred.displayString), so \(resolution.active.displayString) is used for now. Turn off Spotlight's shortcut under Keyboard Shortcuts → Spotlight.")
                    .foregroundStyle(.secondary)
            }
        } else if !hotkeys.isRegistered {
            Text("Shortcut \(hotkeys.activeDisplayString) is used by another app")
                .foregroundStyle(.orange)
        }
    }
}

private struct AppearanceSettings: View {
    @AppStorage(PanelOpacity.activeKey) private var activeOpacity = PanelOpacity.defaultActive
    @AppStorage(PanelOpacity.idleKey) private var idleOpacity = PanelOpacity.defaultIdle
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag(AppAppearance.system)
                    Text("Light").tag(AppAppearance.light)
                    Text("Dark").tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
            }
            Section {
                opacitySlider("While in use", value: $activeOpacity)
                opacitySlider("When idle", value: $idleOpacity)
            } header: {
                Text("Background opacity")
            } footer: {
                Text("Idle means another app is in front and the pointer is outside the panel. Text always stays fully opaque.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { AppAppearance.apply(appearance) }
    }

    private func opacitySlider(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: PanelOpacity.range, step: 0.05)
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

private struct OpenCodeSettings: View {
    let connection: ConnectionManager
    private let server = ServerSettings(defaults: .standard)

    @AppStorage(ConnectionManager.executablePathKey) private var executablePath = ""
    @State private var usesCustomServer = false
    @State private var url = ""
    @State private var password = ""
    @State private var confirmsRestore = false
    @State private var agentError: String?

    var body: some View {
        Form {
            Section("Server") {
                Picker("Server", selection: $usesCustomServer) {
                    Text("Local background service").tag(false)
                    Text("Custom").tag(true)
                }
                .onChange(of: usesCustomServer) {
                    server.usesCustomServer = usesCustomServer
                    connection.retryNow()
                }
                if usesCustomServer {
                    TextField("URL", text: $url, prompt: Text(verbatim: "http://127.0.0.1:4096"))
                    SecureField("Password", text: $password)
                    LabeledContent {
                        Button("Connect", action: applyCustomServer)
                            .disabled(ServerSettings.validURL(url) == nil)
                    } label: {
                        ConnectionStatus(connection: connection)
                    }
                } else {
                    LabeledContent("Status") {
                        ConnectionStatus(connection: connection)
                    }
                }
            }

            Section {
                LabeledContent("opencode executable") {
                    HStack {
                        TextField("opencode executable", text: $executablePath, prompt: Text(detectedPath ?? String(localized: "Not found")))
                            .labelsHidden()
                            .onSubmit(connection.retryNow)
                        Button("Choose…", action: chooseExecutable)
                    }
                }
            } footer: {
                Text("Used to start the background service when it is not running. Leave empty to search the usual install locations.")
                    .settingsFooter()
            }

            Section("Quick Agent") {
                LabeledContent {
                    HStack {
                        Button("Open Agent File", action: openAgentFile)
                        Button("Restore Defaults…") { confirmsRestore = true }
                    }
                } label: {
                    Text(verbatim: QuickAgent.file.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
                if let agentError {
                    Text(agentError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            usesCustomServer = server.usesCustomServer
            url = server.urlString
            password = server.password
        }
        .confirmationDialog("Restore the Quick Agent to its defaults?", isPresented: $confirmsRestore) {
            Button("Restore Defaults", role: .destructive, action: restoreAgent)
        } message: {
            Text("Your changes to the agent file will be lost.")
        }
    }

    private var detectedPath: String? {
        ExecutableLocator.locate(configured: nil)
    }

    private func applyCustomServer() {
        server.urlString = url.trimmingCharacters(in: .whitespaces)
        server.password = password
        connection.retryNow()
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        executablePath = url.path(percentEncoded: false)
        connection.retryNow()
    }

    private func openAgentFile() {
        do {
            try QuickAgent.installIfMissing()
            agentError = nil
            NSWorkspace.shared.open(QuickAgent.file)
        } catch {
            agentError = error.localizedDescription
        }
    }

    private func restoreAgent() {
        do {
            try QuickAgent.restoreDefaults()
            agentError = nil
        } catch {
            agentError = error.localizedDescription
        }
    }
}

struct ConnectionStatus: View {
    let connection: ConnectionManager

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch connection.state {
        case .connected: .green
        case .connecting: .yellow
        case .serviceNotRunning, .opencodeNotFound, .invalidServerURL: .red
        }
    }

    private var label: LocalizedStringKey {
        switch connection.state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .serviceNotRunning: "opencode service is not running"
        case .opencodeNotFound: "opencode is not installed"
        case .invalidServerURL: "The server URL in Settings is not valid"
        }
    }
}

private struct AboutSettings: View {
    @Bindable var updater: Updater

    var body: some View {
        Form {
            LabeledContent("Version", value: Bundle.main.marketingVersion)
            if updater.isAvailable {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                LabeledContent {
                    Button("Check for Updates…", action: updater.checkForUpdates)
                        .disabled(!updater.canCheckForUpdates)
                } label: {
                    EmptyView()
                }
            } else {
                Text("Updates are checked only in release builds.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

enum SystemSettings {
    static func openKeyboardShortcuts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension Text {
    func settingsFooter() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}

extension Bundle {
    var marketingVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
