import Testing
import AppKit
import Carbon.HIToolbox
@testable import FloatingChat

struct HotkeyTests {
    @Test func ignoresDeviceDependentModifierBits() {
        let noisy = Hotkey(keyCode: UInt32(kVK_Space), modifiers: NSEvent.ModifierFlags.command.rawValue | 0x100)
        #expect(noisy == .commandSpace)
    }

    @Test func carbonModifiers() {
        let hotkey = Hotkey(keyCode: UInt32(kVK_Space), modifierFlags: [.command, .option, .control, .shift])
        #expect(hotkey.carbonModifiers == UInt32(cmdKey | optionKey | controlKey | shiftKey))
    }

    @Test func displayString() {
        #expect(Hotkey.commandSpace.displayString == "⌘Space")
        #expect(Hotkey(keyCode: UInt32(kVK_Space), modifierFlags: [.command, .shift, .option, .control]).displayString == "⌃⌥⇧⌘Space")
    }
}

struct SpotlightShortcutTests {
    private func entry(enabled: Int, keyCode: Int = 49, modifiers: Int = 1_048_576) -> [String: Any] {
        ["64": ["enabled": NSNumber(value: enabled), "value": ["parameters": [32, keyCode, modifiers].map(NSNumber.init(value:)), "type": "standard"]]]
    }

    @Test func missingPreferencesMeanMacOSDefault() {
        #expect(SpotlightShortcut.occupiedHotkey(in: nil) == .commandSpace)
        #expect(SpotlightShortcut.occupiedHotkey(in: ["65": [:]]) == .commandSpace)
    }

    @Test func disabledMeansFree() {
        #expect(SpotlightShortcut.occupiedHotkey(in: entry(enabled: 0)) == nil)
    }

    @Test func enabledReturnsConfiguredShortcut() {
        #expect(SpotlightShortcut.occupiedHotkey(in: entry(enabled: 1)) == .commandSpace)
        #expect(SpotlightShortcut.occupiedHotkey(in: entry(enabled: 1, modifiers: 1_572_864))
            == Hotkey(keyCode: 49, modifierFlags: [.command, .option]))
    }
}

struct HotkeyResolverTests {
    @Test func usesPreferredWhenSpotlightDoesNotClash() {
        #expect(HotkeyResolver.resolve(preferred: .commandSpace, spotlight: nil)
            == HotkeyResolution(active: .commandSpace, isFallback: false))
    }

    @Test func fallsBackWhenSpotlightHoldsPreferred() {
        #expect(HotkeyResolver.resolve(preferred: .commandSpace, spotlight: .commandSpace)
            == HotkeyResolution(active: .optionSpace, isFallback: true))
    }

    @Test func customPreferredIsUnaffectedBySpotlight() {
        let custom = Hotkey(keyCode: UInt32(kVK_ANSI_J), modifierFlags: [.control, .option])
        #expect(HotkeyResolver.resolve(preferred: custom, spotlight: .commandSpace)
            == HotkeyResolution(active: custom, isFallback: false))
    }
}

struct DoubleTapDetectorTests {
    private var detector = DoubleTapDetector()

    private mutating func feed(_ steps: [(NSEvent.ModifierFlags, TimeInterval)]) -> [Bool] {
        steps.map { detector.handle($0.0, at: $0.1) }
    }

    @Test mutating func quickDoubleTapFiresOnSecondPress() {
        #expect(feed([(.option, 0), ([], 0.1), (.option, 0.3)]) == [false, false, true])
        // Releasing afterwards and a third tap do not fire again.
        #expect(feed([([], 0.35), (.option, 0.5)]) == [false, false])
    }

    @Test mutating func holdingTooLongDoesNotCount() {
        #expect(feed([(.option, 0), ([], 0.5), (.option, 0.6)]) == [false, false, false])
    }

    @Test mutating func slowSecondTapStartsOver() {
        #expect(feed([(.option, 0), ([], 0.1), (.option, 0.8), ([], 0.9), (.option, 1.0)]) == [false, false, false, false, true])
    }

    @Test mutating func otherModifiersCancel() {
        #expect(feed([(.option, 0), ([.option, .command], 0.05), ([], 0.1), (.option, 0.2)]) == [false, false, false, false])
        #expect(feed([([], 0.3), (.option, 1), ([], 1.1), ([.option, .shift], 1.2)]) == [false, false, false, false])
    }

    @Test mutating func capsLockIsIgnored() {
        #expect(feed([([.option, .capsLock], 0), (.capsLock, 0.1), ([.option, .capsLock], 0.2)]) == [false, false, true])
    }

    @Test mutating func typedKeyInterrupts() {
        _ = feed([(.option, 0), ([], 0.1)])
        detector.interrupt()
        #expect(feed([(.option, 0.2)]) == [false])
    }
}

struct HotkeyTriggerTests {
    @Test func defaultIsDoubleTapOption() {
        #expect(HotkeyTrigger.default == .doubleTapOption)
    }

    @Test func roundTrips() throws {
        for trigger in [HotkeyTrigger.doubleTapOption, .combo(.commandSpace)] {
            let data = try JSONEncoder().encode(trigger)
            #expect(try JSONDecoder().decode(HotkeyTrigger.self, from: data) == trigger)
        }
    }

    @Test func comboNeedsCommandControlOrOption() {
        #expect(Hotkey.optionSpace.isUsableGlobally)
        #expect(!Hotkey(keyCode: UInt32(kVK_ANSI_A), modifierFlags: .shift).isUsableGlobally)
        #expect(!Hotkey(keyCode: UInt32(kVK_ANSI_A), modifierFlags: []).isUsableGlobally)
        #expect(!Hotkey(keyCode: UInt32(kVK_Option), modifierFlags: .command).isUsableGlobally)
    }

    @Test func specialKeyNames() {
        #expect(Hotkey(keyCode: UInt32(kVK_F5), modifierFlags: .control).displayString == "⌃F5")
        #expect(Hotkey(keyCode: UInt32(kVK_UpArrow), modifierFlags: .command).displayString == "⌘↑")
    }

    @MainActor
    @Test func controllerPersistsTrigger() throws {
        let defaults = try #require(UserDefaults(suiteName: "ocf-hotkey-\(UUID().uuidString)"))
        #expect(HotkeyController(defaults: defaults).trigger == .doubleTapOption)
        let combo = HotkeyTrigger.combo(Hotkey(keyCode: UInt32(kVK_ANSI_J), modifierFlags: [.control, .option]))
        HotkeyController(defaults: defaults).setTrigger(combo)
        #expect(HotkeyController(defaults: defaults).trigger == combo)
        GlobalHotkeyRegistrar.shared.unregister()
    }
}

struct ServerSettingsTests {
    @Test func validURL() {
        #expect(ServerSettings.validURL(" http://127.0.0.1:4096 ") != nil)
        #expect(ServerSettings.validURL("https://example.com") != nil)
        #expect(ServerSettings.validURL("127.0.0.1:4096") == nil)
        #expect(ServerSettings.validURL("ftp://example.com") == nil)
        #expect(ServerSettings.validURL("") == nil)
    }

    @Test func customEndpointOnlyWhenEnabledAndValid() throws {
        let defaults = try #require(UserDefaults(suiteName: "ocf-server-\(UUID().uuidString)"))
        let settings = ServerSettings(defaults: defaults)
        settings.urlString = "http://localhost:4096"
        #expect(settings.customEndpoint == nil)
        settings.usesCustomServer = true
        #expect(settings.customEndpoint?.baseURL.absoluteString == "http://localhost:4096")
        settings.urlString = "nonsense"
        #expect(settings.customEndpoint == nil)
    }
}
