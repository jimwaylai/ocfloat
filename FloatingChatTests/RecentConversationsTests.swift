import Testing
import Foundation
@testable import FloatingChat

struct RecentConversationsTests {
    static func session(_ id: String, title: String? = nil, updated: Double = 0) -> SessionInfo {
        SessionInfo(
            id: id, title: title, agent: QuickAgent.id, model: nil, outcome: nil,
            time: .init(created: updated, updated: updated, idle: nil, viewed: nil),
            location: .init(directory: ScratchWorkspace.path)
        )
    }

    let sessions = ["ses_a", "ses_b", "ses_c"].map { Self.session($0) }

    @Test func startsLoadingThenHighlightsCurrent() {
        var recents = RecentConversations(currentID: "ses_b")
        #expect(recents.sessions.isEmpty)
        #expect(recents.highlightedSession == nil)
        recents.load(sessions)
        #expect(recents.highlighted == 1)
        #expect(recents.highlightedSession?.id == "ses_b")
    }

    @Test func newConversationHighlightsFirst() {
        var recents = RecentConversations(currentID: nil)
        recents.load(sessions)
        #expect(recents.highlighted == 0)
    }

    @Test func movingStaysInBounds() {
        var recents = RecentConversations(currentID: nil)
        recents.move(by: 1)
        #expect(recents.highlighted == 0)
        recents.load(sessions)
        recents.move(by: -1)
        #expect(recents.highlighted == 0)
        recents.move(by: 5)
        #expect(recents.highlighted == 2)
        recents.highlight(7)
        #expect(recents.highlighted == 2)
    }

    @Test func failureHasNoRows() {
        var recents = RecentConversations(currentID: nil)
        recents.fail()
        #expect(recents.sessions.isEmpty)
    }
}

@MainActor
struct RecentConversationsModelTests {
    private func makeModel(sessionID: String?) throws -> QuickChatModel {
        let defaults = try #require(UserDefaults(suiteName: "ocf-recents-\(UUID().uuidString)"))
        let store = ConversationStore(defaults: defaults)
        store.sessionID = sessionID
        store.lastInteraction = .now - 3600
        let connection = ConnectionManager(defaults: defaults)
        let conversation = ConversationController(connection: connection, store: store)
        return QuickChatModel(connection: connection, conversation: conversation, defaults: defaults)
    }

    @Test func resumingSwitchesAndCountsAsInteraction() throws {
        let model = try makeModel(sessionID: "ses_current")
        model.draft = "keep me"
        model.openRecent(RecentConversationsTests.session("ses_old", updated: 0))
        #expect(model.conversation.sessionID == "ses_old")
        #expect(model.draft == "keep me")
        model.willSummon()
        #expect(model.conversation.sessionID == "ses_old")
    }

    @Test func choosingTheCurrentOneKeepsIt() throws {
        let model = try makeModel(sessionID: "ses_current")
        let before = model.conversation.lastInteraction
        model.openRecent(RecentConversationsTests.session("ses_current"))
        #expect(model.conversation.sessionID == "ses_current")
        #expect(model.conversation.lastInteraction == before)
    }
}
