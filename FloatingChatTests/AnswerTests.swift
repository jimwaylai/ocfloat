import Testing
import Foundation
@testable import FloatingChat

struct AnswerTests {
    private func event(_ type: String, _ data: String = "{}") throws -> OpenCodeEvent {
        var object = try JSONSerialization.jsonObject(with: Data(data.utf8)) as! [String: Any]
        object["sessionID"] = "ses_1"
        let payload = try JSONSerialization.data(withJSONObject: ["type": type, "data": object])
        return try OpenCodeEvent(json: payload)
    }

    let start = Date(timeIntervalSince1970: 1000)

    private func apply(_ events: [OpenCodeEvent]) -> Answer {
        var answer = Answer()
        for event in events { answer.apply(event, at: start) }
        return answer
    }

    /// Mirrors a recorded run: a web search step, then a step that streams the reply.
    @Test func multiStepAnswerWithToolCall() throws {
        let answer = apply([
            try event("session.execution.started"),
            try event("session.step.started", #"{"agent":"quick-chat","model":{"id":"claude-opus-5-5","providerID":"vertex-anthropic"},"assistantMessageID":"msg_a"}"#),
            try event("session.tool.input.started", #"{"assistantMessageID":"msg_a","id":"toolu_1","name":"websearch"}"#),
            try event("session.tool.called", #"{"assistantMessageID":"msg_a","id":"toolu_1","input":{"query":"latest Swift"},"executed":false}"#),
            try event("session.tool.success", #"{"assistantMessageID":"msg_a","id":"toolu_1","content":[{"type":"text","text":"…"}]}"#),
            try event("session.step.ended", #"{"assistantMessageID":"msg_a","finish":"tool-calls"}"#),
            try event("session.step.started", #"{"model":{"id":"claude-opus-5-5","providerID":"vertex-anthropic"},"assistantMessageID":"msg_b"}"#),
            try event("session.reasoning.started", #"{"assistantMessageID":"msg_b","ordinal":0}"#),
            try event("session.reasoning.ended", #"{"assistantMessageID":"msg_b","ordinal":0,"text":""}"#),
            try event("session.text.started", #"{"assistantMessageID":"msg_b","ordinal":0}"#),
            try event("session.text.delta", #"{"assistantMessageID":"msg_b","ordinal":0,"delta":"- **Swift"}"#),
            try event("session.text.delta", #"{"assistantMessageID":"msg_b","ordinal":0,"delta":" 6.4.3**"}"#),
        ])
        #expect(answer.status == .running)
        #expect(answer.model == ModelRef(providerID: "vertex-anthropic", id: "claude-opus-5-5"))
        #expect(answer.parts == [
            .tool(.init(id: "toolu_1", name: "websearch", subject: "latest Swift", state: .succeeded, output: "…")),
            .reasoning(.init(id: "msg_b/reasoning/0", text: "", started: start, ended: start)),
            .text(id: "msg_b/text/0", text: "- **Swift 6.4.3**"),
        ])
        #expect(answer.text == "- **Swift 6.4.3**")
        #expect(answer.isActive)
    }

    @Test func endedEventCorrectsAccumulatedText() throws {
        var answer = apply([
            try event("session.text.delta", #"{"assistantMessageID":"m","ordinal":0,"delta":"Hel"}"#),
            try event("session.text.ended", #"{"assistantMessageID":"m","ordinal":0,"text":"Hello"}"#),
            try event("session.execution.succeeded"),
        ])
        #expect(answer.text == "Hello")
        #expect(answer.status == .succeeded)
        #expect(!answer.isActive)

        answer.apply(try event("session.text.delta", #"{"assistantMessageID":"m","ordinal":1,"delta":"World"}"#))
        #expect(answer.text == "Hello\n\nWorld")
    }

    @Test func failureCarriesServerMessage() throws {
        let answer = apply([
            try event("session.tool.input.started", #"{"assistantMessageID":"m","id":"t","name":"webfetch"}"#),
            try event("session.tool.failed", #"{"assistantMessageID":"m","id":"t","error":{"type":"x","message":"nope"},"executed":true}"#),
            try event("session.execution.failed", #"{"error":{"type":"provider","message":"Rate limited"}}"#),
        ])
        #expect(answer.parts == [.tool(.init(id: "t", name: "webfetch", state: .failed, output: "nope"))])
        #expect(answer.status == .failed("Rate limited"))
    }

    @Test func reasoningIsTimedAndAccumulated() throws {
        var answer = Answer()
        answer.apply(try event("session.reasoning.started", #"{"assistantMessageID":"m","ordinal":0}"#), at: start)
        answer.apply(try event("session.reasoning.delta", #"{"assistantMessageID":"m","ordinal":0,"delta":"Let me "}"#), at: start + 1)
        answer.apply(try event("session.reasoning.delta", #"{"assistantMessageID":"m","ordinal":0,"delta":"think"}"#), at: start + 2)
        guard case .reasoning(let live) = answer.parts.first else { Issue.record("no reasoning"); return }
        #expect(live.text == "Let me think")
        #expect(live.ended == nil)

        answer.apply(try event("session.reasoning.ended", #"{"assistantMessageID":"m","ordinal":0,"text":"Let me think."}"#), at: start + 4)
        guard case .reasoning(let done) = answer.parts.first else { Issue.record("no reasoning"); return }
        #expect(done.text == "Let me think.")
        #expect(done.duration == 4)
    }

    @Test func longToolOutputIsClipped() throws {
        let long = String(repeating: "x", count: Answer.maximumToolOutput + 100)
        let answer = apply([
            try event("session.tool.input.started", #"{"assistantMessageID":"m","id":"t","name":"webfetch"}"#),
            try event("session.tool.success", #"{"assistantMessageID":"m","id":"t","content":[{"type":"text","text":"\#(long)"}]}"#),
        ])
        guard case .tool(let call) = answer.parts.first else { Issue.record("no tool"); return }
        #expect(call.output?.count == Answer.maximumToolOutput + 2)
    }

    @Test func interruption() throws {
        let answer = apply([try event("session.execution.interrupted", #"{"reason":"user"}"#)])
        #expect(answer.status == .interrupted)
    }
}

struct PanelSizingTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 1000)
    let collapsed = CGRect(x: 400, y: 744, width: 640, height: 56)

    @Test func growsDownwardKeepingTopEdge() {
        let frame = PanelSizing.frame(current: collapsed, preferredHeight: 300, maximumHeight: nil, visibleFrame: screen)
        #expect(frame.maxY == collapsed.maxY)
        #expect(frame.height == 300)
        #expect(frame.minX == collapsed.minX)
        #expect(frame.width == collapsed.width)
    }

    @Test func capsAtSeventyPercentOfScreen() {
        let top = CGRect(x: 400, y: 944, width: 640, height: 56)
        let frame = PanelSizing.frame(current: top, preferredHeight: 5000, maximumHeight: nil, visibleFrame: screen)
        #expect(frame.height == 700)
        #expect(frame.maxY == top.maxY)
    }

    @Test func userMaximumWinsButNeverExceedsScreen() {
        #expect(PanelSizing.frame(current: collapsed, preferredHeight: 5000, maximumHeight: 400, visibleFrame: screen).height == 400)
        #expect(PanelSizing.frame(current: collapsed, preferredHeight: 5000, maximumHeight: 4000, visibleFrame: screen).height == 1000)
    }

    @Test func pushedUpWhenBottomWouldLeaveScreen() {
        let low = CGRect(x: 400, y: 100, width: 640, height: 56)
        let frame = PanelSizing.frame(current: low, preferredHeight: 500, maximumHeight: nil, visibleFrame: screen)
        #expect(frame.minY == screen.minY)
        #expect(frame.height == 500)
    }

    @Test func shrinksBackToInputBar() {
        let expanded = CGRect(x: 400, y: 300, width: 640, height: 500)
        let frame = PanelSizing.frame(current: expanded, preferredHeight: 56, maximumHeight: nil, visibleFrame: screen)
        #expect(frame.height == 56)
        #expect(frame.maxY == expanded.maxY)
    }
}
