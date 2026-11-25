import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press the new combination. `Esc` cancels.
struct HotkeyRecorder: View {
    let hotkeys: HotkeyController
    let current: Hotkey

    @State private var isRecording = false
    @State private var showsModifierHint = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if showsModifierHint {
                Text("Include ⌘, ⌃ or ⌥")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? String(localized: "Press shortcut…") : current.displayString)
                    .frame(minWidth: 110)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        hotkeys.suspend()
        isRecording = true
        showsModifierHint = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]).isEmpty {
                stop()
                return nil
            }
            let hotkey = Hotkey(
                keyCode: UInt32(event.keyCode),
                modifierFlags: event.modifierFlags.intersection([.command, .option, .control, .shift])
            )
            guard hotkey.isUsableGlobally else {
                showsModifierHint = true
                return nil
            }
            stop()
            hotkeys.setTrigger(.combo(hotkey))
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        hotkeys.resume()
    }
}
