import AppKit

/// Remembers the panel's top-left corner separately for each display.
struct PanelPositionStore {
    private static let key = "panelTopLeftByDisplay"
    let defaults: UserDefaults

    func topLeft(for displayID: String) -> CGPoint? {
        guard let xy = defaults.dictionary(forKey: Self.key)?[displayID] as? [Double], xy.count == 2 else { return nil }
        return CGPoint(x: xy[0], y: xy[1])
    }

    func save(_ topLeft: CGPoint, for displayID: String) {
        var all = defaults.dictionary(forKey: Self.key) ?? [:]
        all[displayID] = [Double(topLeft.x), Double(topLeft.y)]
        defaults.set(all, forKey: Self.key)
    }
}

extension NSScreen {
    /// Stable across reboots and display rearrangement, unlike `NSScreenNumber`.
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }
}
