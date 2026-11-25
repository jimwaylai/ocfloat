import AppKit

/// Watches modifier changes system-wide for a double tap of ⌥. Global monitors only see
/// other apps' events, so a local monitor covers the app's own windows.
@MainActor
final class ModifierDoubleTapMonitor {
    var onDoubleTap: (() -> Void)?

    private var detector = DoubleTapDetector()
    private var monitors: [Any] = []

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        detector = DoubleTapDetector()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            detector.interrupt()
        } else if detector.handle(event.modifierFlags, at: event.timestamp) {
            onDoubleTap?()
        }
    }
}
