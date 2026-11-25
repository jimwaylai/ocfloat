import Foundation
import Observation

/// The chat models available in the Scratch Workspace, reloaded on every (re)connect.
@MainActor
@Observable
final class ModelCatalog {
    private(set) var models: [ModelInfo] = []
    /// What a session uses when it has no model of its own.
    private(set) var defaultModel: ModelRef?

    @ObservationIgnored private let connection: ConnectionManager
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init(connection: ConnectionManager) {
        self.connection = connection
        let events = connection.events()
        eventTask = Task { [weak self] in
            for await event in events where event.type == "server.connected" {
                await self?.reload()
            }
        }
        if connection.state == .connected {
            Task { await reload() }
        }
    }

    func info(for ref: ModelRef) -> ModelInfo? {
        models.first { $0.ref.isSameModel(as: ref) }
    }

    /// Whether `ref` can still be used; unknown while the catalog has not loaded.
    func isAvailable(_ ref: ModelRef) -> Bool {
        models.isEmpty || info(for: ref) != nil
    }

    /// Falls back to the raw ID for models the catalog does not know (yet).
    func displayName(for ref: ModelRef) -> String {
        info(for: ref)?.name ?? ref.id
    }

    private func reload() async {
        guard let client = connection.client,
              let models = try? await client.listModels(directory: ScratchWorkspace.path)
        else { return }
        self.models = models
        defaultModel = try? await client.defaultModel(directory: ScratchWorkspace.path).ref
    }
}

/// The model new Conversations start with: the last one the user picked.
struct PreferredModelStore {
    private static let key = "preferredModel"
    let defaults: UserDefaults

    var model: ModelRef? {
        get { defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ModelRef.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.key) }
    }
}
