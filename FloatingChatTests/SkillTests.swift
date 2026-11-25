import Foundation
import Testing
@testable import FloatingChat

struct SkillMenuTests {
    private static let skills = [
        SkillInfo(id: "tdd", name: "tdd", description: "Test-driven development."),
        SkillInfo(id: "eng", name: "eng", description: "Translate Chinese to English."),
        SkillInfo(id: "opencode", name: "OpenCode", description: "Questions about OpenCode."),
        SkillInfo(id: "code-review", name: "code-review", description: "Review changes."),
    ]

    @Test func queryOnlyForASingleSlashWord() {
        #expect(SkillMenu.query(in: "/") == "")
        #expect(SkillMenu.query(in: "/en") == "en")
        #expect(SkillMenu.query(in: "/eng hello") == nil)
        #expect(SkillMenu.query(in: "hello /eng") == nil)
        #expect(SkillMenu.query(in: "") == nil)
    }

    @Test func emptyQueryListsAllByName() {
        let menu = SkillMenu(state: .loaded(Self.skills), query: "")
        #expect(menu.matches.map(\.id) == ["code-review", "eng", "opencode", "tdd"])
    }

    @Test func prefixMatchesComeFirstThenContainsThenDescription() {
        var menu = SkillMenu(state: .loaded(Self.skills), query: "code")
        #expect(menu.matches.map(\.id) == ["code-review", "opencode"])
        menu.setQuery("eng")
        // "eng" by name; nothing else names it, "English" is only in a description.
        #expect(menu.matches.map(\.id) == ["eng"])
        menu.setQuery("chinese")
        #expect(menu.matches.map(\.id) == ["eng"])
        menu.setQuery("zzz")
        #expect(menu.matches.isEmpty)
        #expect(menu.highlightedSkill == nil)
    }

    @Test func highlightMovesWithinMatchesAndResetsOnQuery() {
        var menu = SkillMenu(state: .loaded(Self.skills), query: "")
        menu.move(by: 10)
        #expect(menu.highlightedSkill?.id == "tdd")
        menu.move(by: -1)
        #expect(menu.highlightedSkill?.id == "opencode")
        menu.setQuery("e")
        #expect(menu.highlighted == 0)
    }

    @Test func loadingThenLoadedOrFailed() {
        var menu = SkillMenu(state: .loading, query: "")
        #expect(menu.matches.isEmpty)
        menu.load(Self.skills)
        #expect(menu.matches.count == 4)
        menu.fail()
        #expect(menu.state == .loaded(Self.skills))
    }
}

struct SkillHistoryTests {
    @Test func skillMessageAttachesToTheNextQuestion() throws {
        let json = #"""
        {"data":[
          {"id":"msg_s","type":"skill","skill":"eng","name":"eng","text":"# English Assistant"},
          {"id":"msg_u1","type":"user","text":"今天天氣很好"},
          {"id":"msg_a1","type":"assistant","content":[{"type":"text","text":"The weather is great today."}]},
          {"id":"msg_i1","type":"idle","outcome":"succeeded"},
          {"id":"msg_u2","type":"user","text":"再一句"}
        ]}
        """#
        let messages = try JSONDecoder().decode(DataEnvelope<LenientList<SessionMessage>>.self, from: Data(json.utf8)).data.elements
        let turns = ConversationHistory.turns(from: messages)
        #expect(turns.map(\.skill) == ["eng", nil])
        #expect(turns[0].answer.text == "The weather is great today.")
    }

    @Test func decodesSkillList() throws {
        let json = #"{"location":{},"data":[{"id":"eng","name":"eng","description":"Translate","path":"/x/SKILL.md","content":"…"},{"id":"mcp","name":"MCP","path":"skill://mcp","content":""}]}"#
        let skills = try JSONDecoder().decode(DataEnvelope<LenientList<SkillInfo>>.self, from: Data(json.utf8)).data.elements
        #expect(skills == [SkillInfo(id: "eng", name: "eng", description: "Translate"), SkillInfo(id: "mcp", name: "MCP", description: nil)])
    }
}

@MainActor
struct DraftSkillTests {
    private func makeModel() throws -> QuickChatModel {
        let defaults = try #require(UserDefaults(suiteName: "ocf-skill-\(UUID().uuidString)"))
        let connection = ConnectionManager(defaults: defaults)
        let conversation = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))
        return QuickChatModel(connection: connection, conversation: conversation, defaults: defaults)
    }

    @Test func slashOpensMenuAndSpaceClosesIt() throws {
        let model = try makeModel()
        model.draft = "/"
        #expect(model.skillMenu != nil)
        model.draft = "/en"
        #expect(model.skillMenu?.query == "en")
        model.draft = "/en "
        #expect(model.skillMenu == nil)
    }

    @Test func escapeKeepsMenuClosedUntilTheSlashWordEnds() throws {
        let model = try makeModel()
        model.draft = "/x"
        model.dismissSkillMenu()
        model.draft = "/xy"
        #expect(model.skillMenu == nil)
        model.draft = ""
        model.draft = "/"
        #expect(model.skillMenu != nil)
    }

    @Test func choosingASkillClearsTheSlashWord() throws {
        let model = try makeModel()
        model.draft = "/eng"
        let skill = SkillInfo(id: "eng", name: "eng", description: nil)
        model.selectSkill(skill)
        #expect(model.selectedSkill == skill)
        #expect(model.draft.isEmpty)
        #expect(model.skillMenu == nil)
        model.removeSelectedSkill()
        #expect(model.selectedSkill == nil)
    }
}
