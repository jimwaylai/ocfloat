import Foundation
import Observation
import Sparkle

/// Sparkle updates. Only release builds with a feed key check for updates: debug builds
/// are ad-hoc signed and would fail Sparkle's signature check anyway.
@MainActor
@Observable
final class Updater {
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(bundle: Bundle = .main) {
        guard Self.isConfigured(bundle) else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecks = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private static func isConfigured(_ bundle: Bundle) -> Bool {
        #if DEBUG
        return false
        #else
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        return !key.isEmpty && !feed.contains("/OWNER/")
        #endif
    }
}
