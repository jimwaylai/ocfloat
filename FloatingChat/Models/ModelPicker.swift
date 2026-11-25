import Foundation

/// The model menu: a searchable list of models, with a second level for a model's variants.
/// It lives inside the panel rather than in a popover, because the app never activates and
/// a popover could not take keyboard focus.
struct ModelPicker {
    struct Section: Identifiable {
        let providerID: String
        let models: [ModelInfo]
        var id: String { providerID }
    }

    enum Level {
        case models
        case variants(ModelInfo)
    }

    let models: [ModelInfo]
    /// What the Conversation uses now; marked with a checkmark and highlighted on open.
    let current: ModelRef?
    private(set) var level = Level.models
    private(set) var highlighted = 0

    var query = "" {
        // The search field writes back unchanged values, e.g. when it appears.
        didSet { if query != oldValue { highlighted = 0 } }
    }

    init(models: [ModelInfo], current: ModelRef?) {
        self.models = models
        self.current = current
        if let current, let index = filteredModels.firstIndex(where: { $0.ref.isSameModel(as: current) }) {
            highlighted = index
        }
    }

    /// Matches every word of the query against the name, ID and provider, grouped by
    /// provider in the server's order.
    var sections: [Section] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matching = models.filter { model in
            let haystack = "\(model.name) \(model.id) \(model.providerID)"
            return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
        var order: [String] = []
        var grouped: [String: [ModelInfo]] = [:]
        for model in matching {
            if grouped[model.providerID] == nil { order.append(model.providerID) }
            grouped[model.providerID, default: []].append(model)
        }
        return order.map { Section(providerID: $0, models: grouped[$0] ?? []) }
    }

    /// The rows of the models level in display order; `highlighted` indexes into it.
    var filteredModels: [ModelInfo] {
        sections.flatMap(\.models)
    }

    /// The rows of the variants level: `nil` is the model's default.
    var variantRows: [String?] {
        guard case .variants(let model) = level else { return [] }
        return [nil] + model.variantIDs
    }

    private var rowCount: Int {
        switch level {
        case .models: filteredModels.count
        case .variants: variantRows.count
        }
    }

    var highlightedHasVariants: Bool {
        guard case .models = level else { return false }
        let models = filteredModels
        return models.indices.contains(highlighted) && !models[highlighted].variantIDs.isEmpty
    }

    mutating func highlight(_ index: Int) {
        guard (0..<rowCount).contains(index) else { return }
        highlighted = index
    }

    mutating func move(by offset: Int) {
        guard rowCount > 0 else { return }
        highlighted = min(max(highlighted + offset, 0), rowCount - 1)
    }

    /// Chooses the highlighted row. A model with variants opens its second level instead
    /// and returns `nil`.
    mutating func activate() -> ModelRef? {
        switch level {
        case .models:
            let models = filteredModels
            guard models.indices.contains(highlighted) else { return nil }
            let model = models[highlighted]
            guard !model.variantIDs.isEmpty else { return model.ref }
            level = .variants(model)
            let currentVariant = current.flatMap { $0.isSameModel(as: model.ref) ? $0.variant : nil }
            highlighted = variantRows.firstIndex(of: currentVariant) ?? 0
            return nil
        case .variants(let model):
            let rows = variantRows
            guard rows.indices.contains(highlighted) else { return nil }
            return ModelRef(providerID: model.providerID, id: model.id, variant: rows[highlighted])
        }
    }

    /// Leaves the variants level; returns `false` at the top level, where the menu should close.
    mutating func back() -> Bool {
        guard case .variants(let model) = level else { return false }
        level = .models
        highlighted = filteredModels.firstIndex { $0.ref.isSameModel(as: model.ref) } ?? 0
        return true
    }
}
