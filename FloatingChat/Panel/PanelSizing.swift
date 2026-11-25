import Foundation

enum PanelSizing {
    static let maximumScreenFraction: CGFloat = 0.7

    /// Keeps the top edge where it is and grows or shrinks downward. The height is capped
    /// at the user's chosen maximum, or 70% of the screen, and the frame is pushed up only
    /// when its bottom would leave the screen.
    static func frame(current: CGRect, preferredHeight: CGFloat, maximumHeight: CGFloat?, visibleFrame: CGRect) -> CGRect {
        let limit = min(maximumHeight ?? visibleFrame.height * maximumScreenFraction, visibleFrame.height)
        let height = min(preferredHeight, limit).rounded(.up)
        let y = max(current.maxY - height, visibleFrame.minY)
        return CGRect(x: current.minX, y: y, width: current.width, height: height)
    }
}

/// Remembers the width and maximum height the user dragged the panel to.
struct PanelSizeStore {
    private static let widthKey = "panelWidth"
    private static let maximumHeightKey = "panelMaximumHeight"
    let defaults: UserDefaults

    var width: CGFloat? {
        get { defaults.object(forKey: Self.widthKey) as? CGFloat }
        nonmutating set { defaults.set(newValue, forKey: Self.widthKey) }
    }

    var maximumHeight: CGFloat? {
        get { defaults.object(forKey: Self.maximumHeightKey) as? CGFloat }
        nonmutating set { defaults.set(newValue, forKey: Self.maximumHeightKey) }
    }
}
