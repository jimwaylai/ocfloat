import AppKit
import Carbon.HIToolbox

struct Hotkey: Equatable, Codable, Sendable {
    let keyCode: UInt32
    /// Device-independent `NSEvent.ModifierFlags` raw value.
    let modifiers: UInt

    init(keyCode: UInt32, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
    }

    init(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        self.init(keyCode: keyCode, modifiers: modifierFlags.rawValue)
    }

    static let commandSpace = Hotkey(keyCode: UInt32(kVK_Space), modifierFlags: .command)
    static let optionSpace = Hotkey(keyCode: UInt32(kVK_Space), modifierFlags: .option)

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifierFlags.contains(.command) { result |= cmdKey }
        if modifierFlags.contains(.option) { result |= optionKey }
        if modifierFlags.contains(.control) { result |= controlKey }
        if modifierFlags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    var displayString: String {
        var symbols = ""
        if modifierFlags.contains(.control) { symbols += "⌃" }
        if modifierFlags.contains(.option) { symbols += "⌥" }
        if modifierFlags.contains(.shift) { symbols += "⇧" }
        if modifierFlags.contains(.command) { symbols += "⌘" }
        return symbols + keyName
    }

    /// A combination needs ⌘, ⌃ or ⌥: with only ⇧ or none it would swallow regular typing.
    var isUsableGlobally: Bool {
        !modifierFlags.intersection([.command, .control, .option]).isEmpty
            && !Self.modifierKeyCodes.contains(Int(keyCode))
    }

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function,
    ]

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private var keyName: String {
        if let name = Self.specialKeyNames[Int(keyCode)] { return name }
        return Self.character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// The character the key types in the current keyboard layout, without modifiers.
    private static func character(for keyCode: UInt32) -> String? {
        // Input methods such as Zhuyin have no layout data; their ASCII layout does.
        let sources = [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()]
            .compactMap { $0?.takeRetainedValue() }
        guard let pointer = sources.lazy.compactMap({ TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }).first
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer in
            UCKeyTranslate(
                buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let result = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
