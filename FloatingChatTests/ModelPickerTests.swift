import Testing
import Foundation
@testable import FloatingChat

struct ModelPickerTests {
    private static func info(_ providerID: String, _ id: String, _ name: String, variants: [String] = []) -> ModelInfo {
        ModelInfo(id: id, providerID: providerID, name: name, variants: variants.map(ModelInfo.Variant.init), capabilities: nil, enabled: true)
    }

    let models = [
        info("opencode", "iceman-free", "Iceman Free"),
        info("openai", "gpt-6.1", "GPT-6.1", variants: ["low", "high"]),
        info("opencode", "hy4-flash-free", "Hy4 flash Free", variants: ["none", "high"]),
        info("vertex-anthropic", "claude-opus-5-5", "Claude Opus 5.5 (Vertex)", variants: ["low", "medium", "high"]),
    ]

    @Test func groupsByProviderInServerOrder() {
        let picker = ModelPicker(models: models, current: nil)
        #expect(picker.sections.map(\.providerID) == ["opencode", "openai", "vertex-anthropic"])
        #expect(picker.filteredModels.map(\.id) == ["iceman-free", "hy4-flash-free", "gpt-6.1", "claude-opus-5-5"])
    }

    @Test func searchMatchesEveryWordAgainstNameIDAndProvider() {
        var picker = ModelPicker(models: models, current: nil)
        picker.query = "free"
        #expect(picker.filteredModels.map(\.id) == ["iceman-free", "hy4-flash-free"])
        picker.query = "OPUS vertex"
        #expect(picker.filteredModels.map(\.id) == ["claude-opus-5-5"])
        picker.query = "opus openai"
        #expect(picker.sections.isEmpty)
    }

    @Test func opensOnCurrentModelAndSearchResetsHighlight() {
        var picker = ModelPicker(models: models, current: ModelRef(providerID: "openai", id: "gpt-6.1", variant: "high"))
        #expect(picker.highlighted == 2)
        picker.query = ""
        #expect(picker.highlighted == 2)
        picker.query = "c"
        #expect(picker.highlighted == 0)
    }

    @Test func movingStaysInBounds() {
        var picker = ModelPicker(models: models, current: nil)
        picker.move(by: -1)
        #expect(picker.highlighted == 0)
        picker.move(by: 10)
        #expect(picker.highlighted == 3)
        picker.highlight(9)
        #expect(picker.highlighted == 3)
    }

    @Test func modelWithoutVariantsIsChosenDirectly() {
        var picker = ModelPicker(models: models, current: nil)
        #expect(!picker.highlightedHasVariants)
        let chosen = picker.activate()
        #expect(chosen == ModelRef(providerID: "opencode", id: "iceman-free"))
    }

    @Test func variantsAreASecondLevelStartingAtTheCurrentOne() throws {
        var picker = ModelPicker(models: models, current: ModelRef(providerID: "vertex-anthropic", id: "claude-opus-5-5", variant: "medium"))
        #expect(picker.highlightedHasVariants)
        let chosen = picker.activate()
        #expect(chosen == nil)
        #expect(picker.variantRows == [nil, "low", "medium", "high"])
        #expect(picker.highlighted == 2)

        picker.move(by: -2)
        let chosenDefault = picker.activate()
        #expect(chosenDefault == ModelRef(providerID: "vertex-anthropic", id: "claude-opus-5-5", variant: nil))
        picker.move(by: 3)
        let chosenHigh = picker.activate()
        #expect(chosenHigh == ModelRef(providerID: "vertex-anthropic", id: "claude-opus-5-5", variant: "high"))
    }

    @Test func variantsOfAnotherModelStartAtDefault() {
        var picker = ModelPicker(models: models, current: ModelRef(providerID: "vertex-anthropic", id: "claude-opus-5-5", variant: "high"))
        picker.highlight(2)
        _ = picker.activate()
        #expect(picker.highlighted == 0)
    }

    @Test func backReturnsToTheModelThenCloses() {
        var picker = ModelPicker(models: models, current: nil)
        picker.query = "flash"
        _ = picker.activate()
        let wentBack = picker.back()
        #expect(wentBack)
        #expect(picker.filteredModels[picker.highlighted].id == "hy4-flash-free")
        #expect(picker.query == "flash")
        let closes = !picker.back()
        #expect(closes)
    }
}

@MainActor
struct PreferredModelTests {
    private func makeModel() throws -> QuickChatModel {
        let defaults = try #require(UserDefaults(suiteName: "ocf-model-\(UUID().uuidString)"))
        let connection = ConnectionManager(defaults: defaults)
        let conversation = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))
        return QuickChatModel(connection: connection, conversation: conversation, defaults: defaults)
    }

    @Test func storeRoundTripsVariant() throws {
        let defaults = try #require(UserDefaults(suiteName: "ocf-model-\(UUID().uuidString)"))
        let store = PreferredModelStore(defaults: defaults)
        #expect(store.model == nil)
        store.model = ModelRef(providerID: "openai", id: "gpt-6.1", variant: "high")
        #expect(PreferredModelStore(defaults: defaults).model == ModelRef(providerID: "openai", id: "gpt-6.1", variant: "high"))
        store.model = nil
        #expect(store.model == nil)
    }

    @Test func choosingAppliesNowAndToNewConversations() throws {
        let model = try makeModel()
        let choice = ModelRef(providerID: "openai", id: "gpt-6.1", variant: "low")
        model.chooseModel(choice)
        #expect(model.conversation.model == choice)
        #expect(model.currentModel == choice)
        #expect(model.currentModelLabel == "gpt-6.1 · low")

        model.conversation.startNew()
        #expect(model.conversation.model == nil)
        #expect(model.currentModel == choice)
        #expect(model.conversation.newSessionModel() == choice)
    }
}
