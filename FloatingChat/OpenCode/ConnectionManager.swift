import Foundation
import Observation

enum ConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case serviceNotRunning
    case opencodeNotFound
    /// The custom server URL in Settings is empty or malformed.
    case invalidServerURL
}

/// Keeps one live connection to the opencode server: discovers the background service,
/// starts it once if needed, holds the event stream open and reconnects with backoff.
@MainActor
@Observable
final class ConnectionManager {
    static let executablePathKey = "opencodeExecutablePath"
    private static let maxBackoff: Duration = .seconds(15)

    private(set) var state: ConnectionState = .connecting
    private(set) var client: OpenCodeClient?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var autoStartAttempted = false
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<OpenCodeEvent>.Continuation] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { await run() }
    }

    /// Skips the current backoff wait.
    func retryNow() {
        runTask?.cancel()
        runTask = nil
        start()
    }

    /// Explicit user request, e.g. from a "Start" button; overrides the one-shot auto start.
    func startService() {
        autoStartAttempted = false
        retryNow()
    }

    /// Every event from the server's global stream, across reconnects.
    func events() -> AsyncStream<OpenCodeEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: OpenCodeEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    private func run() async {
        var backoff: Duration = .seconds(1)
        while !Task.isCancelled {
            if let endpoint = await resolveEndpoint() {
                state = .connecting
                let client = OpenCodeClient(endpoint: endpoint)
                do {
                    _ = try await client.info()
                    for try await event in client.events() {
                        if event.type == "server.connected" {
                            self.client = client
                            state = .connected
                            autoStartAttempted = false
                            backoff = .seconds(1)
                        }
                        for subscriber in subscribers.values { subscriber.yield(event) }
                    }
                } catch {
                    // Dropped or refused; fall through to reconnect.
                }
                self.client = nil
                if !Task.isCancelled, state == .connected { state = .connecting }
            }
            guard (try? await Task.sleep(for: backoff)) != nil else { return }
            backoff = min(backoff * 2, Self.maxBackoff)
        }
    }

    private func resolveEndpoint() async -> OpenCodeEndpoint? {
        let server = ServerSettings(defaults: defaults)
        if server.usesCustomServer {
            guard let endpoint = server.customEndpoint else {
                state = .invalidServerURL
                return nil
            }
            return endpoint
        }
        if let service = ServiceDiscovery.read() { return OpenCodeEndpoint(service) }

        guard let executable = ExecutableLocator.locate(configured: defaults.string(forKey: Self.executablePathKey)) else {
            state = .opencodeNotFound
            return nil
        }
        guard !autoStartAttempted else {
            state = .serviceNotRunning
            return nil
        }
        autoStartAttempted = true
        state = .connecting
        _ = await ServiceLauncher.start(executable: executable)
        for _ in 0..<10 {
            if let service = ServiceDiscovery.read() { return OpenCodeEndpoint(service) }
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return nil }
        }
        state = .serviceNotRunning
        return nil
    }
}
