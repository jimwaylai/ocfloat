import Carbon.HIToolbox

/// Registers a single system-wide hotkey through Carbon, which still is the only public API
/// for global hotkeys that does not require Accessibility permission.
@MainActor
final class GlobalHotkeyRegistrar {
    static let shared = GlobalHotkeyRegistrar()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Returns false when another app already owns the combination.
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4F43_4654), id: 1) // "OCFT"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalHotkeyRegistrar.shared.onPress?() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }
}
