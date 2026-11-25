import CoreGraphics

/// The panel is anchored by its top-left corner because it grows downward as a Conversation expands.
enum PanelPlacement {
    static func frame(size: CGSize, visibleFrame: CGRect, savedTopLeft: CGPoint?) -> CGRect {
        let topLeft = savedTopLeft ?? CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - visibleFrame.height * 0.2
        )
        let x = max(visibleFrame.minX, min(topLeft.x, visibleFrame.maxX - size.width))
        let y = max(visibleFrame.minY, min(topLeft.y - size.height, visibleFrame.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
