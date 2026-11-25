import Testing
import Foundation
@testable import FloatingChat

struct ConversationHistoryTests {
    /// Trimmed from a recorded `GET /api/session/{id}/message?order=asc` response.
    static let recorded = #"""
    {"data":[
      {"id":"msg_u1","time":{"created":1},"text":"Current Swift version?","type":"user","content":null},
      {"id":"msg_a1","type":"assistant","agent":"quick-chat","model":{"id":"claude-opus-5-5","providerID":"vertex-anthropic"},
       "content":[{"type":"tool","id":"toolu_1","name":"websearch","executed":false,"state":{"status":"completed","input":{"query":"latest Swift"},"content":[{"type":"text","text":"Swift 6.4.1 released"}]}}],
       "finish":"tool-calls"},
      {"id":"msg_m","type":"model-switched","model":{"id":"x","providerID":"y"}},
      {"id":"msg_a2","type":"assistant","model":{"id":"claude-opus-5-5","providerID":"vertex-anthropic"},
       "content":[{"type":"reasoning","text":"","native":{"signature":"…"},"time":{"created":1795570892688,"completed":1795570893396}},{"type":"text","text":"**Swift 6.4.1**"},{"type":"future-kind"}]},
      {"id":"msg_i1","type":"idle","outcome":"succeeded","content":null},
      {"id":"msg_u2","text":"And Xcode?","type":"user"},
      {"id":"msg_a3","type":"assistant","content":[{"type":"text","text":"Partial"}]},
      {"id":"msg_i2","type":"idle","outcome":"failed","error":{"type":"provider","message":"Overloaded"}},
      {"id":"msg_u3","text":"Still going?","type":"user"},
      {"id":"msg_a4","type":"assistant","content":[{"type":"text","text":"Yes"},{"type":"text","text":"more"}]}
    ],"cursor":{"previous":"a","next":"b"}}
    """#

    @Test func rebuildsTurnsFromMessages() throws {
        let messages = try JSONDecoder().decode(DataEnvelope<LenientList<SessionMessage>>.self, from: Data(Self.recorded.utf8)).data.elements
        let turns = ConversationHistory.turns(from: messages)
        try #require(turns.count == 3)

        #expect(turns[0].id == "msg_u1")
        #expect(turns[0].question == "Current Swift version?")
        #expect(turns[0].answer.status == .succeeded)
        #expect(turns[0].answer.model == ModelRef(providerID: "vertex-anthropic", id: "claude-opus-5-5"))
        #expect(turns[0].messageID == "msg_u1")
        #expect(turns[0].answer.parts == [
            .tool(.init(id: "toolu_1", name: "websearch", subject: "latest Swift", state: .succeeded, output: "Swift 6.4.1 released")),
            .reasoning(.init(
                id: "msg_a2/reasoning/0",
                text: "",
                started: Date(timeIntervalSince1970: 1795570892.688),
                ended: Date(timeIntervalSince1970: 1795570893.396)
            )),
            .text(id: "msg_a2/text/0", text: "**Swift 6.4.1**"),
        ])

        #expect(turns[1].answer.status == .failed("Overloaded"))
        #expect(turns[1].answer.text == "Partial")

        // No idle message yet: still answering, and live events continue the same parts.
        #expect(turns[2].answer.status == .running)
        #expect(turns[2].answer.parts.map(\.id) == ["msg_a4/text/0", "msg_a4/text/1"])
    }

    @Test func skipsMalformedMessages() throws {
        let json = #"{"data":[{"type":"user"},{"id":"msg_u","type":"user","text":"Hi"},42]}"#
        let messages = try JSONDecoder().decode(DataEnvelope<LenientList<SessionMessage>>.self, from: Data(json.utf8)).data.elements
        #expect(ConversationHistory.turns(from: messages).map(\.question) == ["Hi"])
    }
}

struct IdleResetTests {
    let now = Date(timeIntervalSince1970: 100_000)
    let tenMinutes: TimeInterval = 600

    @Test func resetsOnlyAfterThreshold() {
        #expect(IdleReset.shouldReset(lastInteraction: now - 601, now: now, threshold: tenMinutes, hasUnreadAnswer: false, isAnswering: false))
        #expect(!IdleReset.shouldReset(lastInteraction: now - 599, now: now, threshold: tenMinutes, hasUnreadAnswer: false, isAnswering: false))
    }

    @Test func unreadAnswerOrRunningAnswerKeepsConversation() {
        #expect(!IdleReset.shouldReset(lastInteraction: now - 3600, now: now, threshold: tenMinutes, hasUnreadAnswer: true, isAnswering: false))
        #expect(!IdleReset.shouldReset(lastInteraction: now - 3600, now: now, threshold: tenMinutes, hasUnreadAnswer: false, isAnswering: true))
    }

    @Test func noInteractionMeansNothingToReset() {
        #expect(!IdleReset.shouldReset(lastInteraction: nil, now: now, threshold: tenMinutes, hasUnreadAnswer: false, isAnswering: false))
    }

    @Test func thresholdFromSettings() throws {
        let defaults = try #require(UserDefaults(suiteName: "ocf-idle-\(UUID().uuidString)"))
        #expect(IdleReset.threshold(defaults: defaults) == 600)
        defaults.set(3, forKey: IdleReset.minutesKey)
        #expect(IdleReset.threshold(defaults: defaults) == 180)
    }
}

@MainActor
struct SummonTests {
    private func makeModel(lastInteraction: Date?, sessionID: String? = "ses_old", draft: String = "") throws -> (QuickChatModel, ConversationStore) {
        let defaults = try #require(UserDefaults(suiteName: "ocf-summon-\(UUID().uuidString)"))
        let store = ConversationStore(defaults: defaults)
        store.sessionID = sessionID
        store.lastInteraction = lastInteraction
        let connection = ConnectionManager(defaults: defaults)
        let model = QuickChatModel(connection: connection, conversation: ConversationController(connection: connection, store: store), defaults: defaults)
        model.draft = draft
        return (model, store)
    }

    @Test func idleConversationIsReplacedAndDraftKept() throws {
        let last = Date.now - 20 * 60
        let (model, store) = try makeModel(lastInteraction: last, draft: "half-written")
        model.willSummon()
        #expect(model.conversation.sessionID == nil)
        #expect(store.sessionID == nil)
        #expect(model.previousConversation == .init(sessionID: "ses_old", lastInteraction: last))
        #expect(model.draft == "half-written")
        #expect(!model.isExpanded)
    }

    @Test func recentConversationIsKept() throws {
        let (model, _) = try makeModel(lastInteraction: .now - 60)
        model.willSummon()
        #expect(model.conversation.sessionID == "ses_old")
        #expect(model.previousConversation == nil)
    }

    @Test func backToPreviousRestoresIt() throws {
        let last = Date.now - 20 * 60
        let (model, store) = try makeModel(lastInteraction: last)
        model.willSummon()
        model.returnToPreviousConversation()
        #expect(model.conversation.sessionID == "ses_old")
        #expect(model.conversation.lastInteraction == last)
        #expect(store.sessionID == "ses_old")
        #expect(model.previousConversation == nil)
    }

    @Test func newConversationClearsButKeepsDraft() throws {
        let (model, store) = try makeModel(lastInteraction: .now, draft: "keep me")
        model.newConversation()
        #expect(model.conversation.isEmpty)
        #expect(store.sessionID == nil)
        #expect(model.draft == "keep me")
        #expect(model.previousConversation == nil)
    }
}

@MainActor
struct PanelOpacityTests {
    @Test func activeWhileKeyOrHovered() throws {
        let defaults = try #require(UserDefaults(suiteName: "ocf-opacity-\(UUID().uuidString)"))
        let connection = ConnectionManager(defaults: defaults)
        let model = QuickChatModel(connection: connection, conversation: ConversationController(connection: connection, store: ConversationStore(defaults: defaults)), defaults: defaults)
        #expect(!model.isPanelActive)
        model.isPointerInside = true
        #expect(model.isPanelActive)
        model.isPointerInside = false
        model.isPanelKey = true
        #expect(model.isPanelActive)
    }

    @Test func valuesAreClamped() {
        #expect(PanelOpacity.clamped(0) == PanelOpacity.range.lowerBound)
        #expect(PanelOpacity.clamped(1.5) == 1)
        #expect(PanelOpacity.clamped(0.6) == 0.6)
    }
}
