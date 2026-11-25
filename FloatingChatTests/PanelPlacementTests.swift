import Testing
import CoreGraphics
@testable import FloatingChat

struct PanelPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let size = CGSize(width: 640, height: 56)

    @Test func defaultsToCenteredNearTop() {
        let frame = PanelPlacement.frame(size: size, visibleFrame: screen, savedTopLeft: nil)
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY - screen.height * 0.2)
    }

    @Test func restoresSavedTopLeft() {
        let frame = PanelPlacement.frame(size: size, visibleFrame: screen, savedTopLeft: CGPoint(x: 100, y: 700))
        #expect(frame.origin == CGPoint(x: 100, y: 644))
    }

    @Test func clampsIntoVisibleFrame() {
        let frame = PanelPlacement.frame(size: size, visibleFrame: screen, savedTopLeft: CGPoint(x: 1400, y: 2000))
        #expect(frame.maxX == screen.maxX)
        #expect(frame.maxY == screen.maxY)
    }

    @Test func clampsOnSecondaryScreenWithNegativeOrigin() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = PanelPlacement.frame(size: size, visibleFrame: left, savedTopLeft: CGPoint(x: 0, y: 500))
        #expect(frame.maxX == left.maxX)
        #expect(frame.minX >= left.minX)
    }
}
