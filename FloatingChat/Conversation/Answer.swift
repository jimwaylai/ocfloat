import Foundation

/// The reply to one question. It is built from the session's event stream and may span
/// several assistant messages (one per step) until the execution finishes.
struct Answer: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting
        case running
        case succeeded
        case failed(String)
        case interrupted
    }

    struct Reasoning: Equatable, Sendable {
        let id: String
        var text: String
        var started: Date?
        var ended: Date?

        var duration: TimeInterval? {
            guard let started, let ended else { return nil }
            return ended.timeIntervalSince(started)
        }
    }

    struct ToolCall: Equatable, Sendable {
        enum State: Equatable, Sendable {
            case running
            case succeeded
            case failed
        }

        let id: String
        var name: String
        var subject: String?
        var state: State = .running
        /// The tool's result or error, shown when the call is expanded.
        var output: String?
    }

    enum Part: Equatable, Sendable, Identifiable {
        case text(id: String, text: String)
        case reasoning(Reasoning)
        case tool(ToolCall)

        var id: String {
            switch self {
            case .text(let id, _): id
            case .reasoning(let reasoning): reasoning.id
            case .tool(let call): call.id
            }
        }
    }

    /// Long tool results (fetched pages) are cut to keep the transcript light.
    static let maximumToolOutput = 4000

    var parts: [Part] = []
    var status: Status = .waiting
    var model: ModelRef?

    var isActive: Bool { status == .waiting || status == .running }

    var text: String {
        parts.compactMap { if case .text(_, let text) = $0 { text } else { nil } }
            .joined(separator: "\n\n")
    }

    mutating func apply(_ event: OpenCodeEvent, at now: Date = .now) {
        guard let payload = try? event.decodeData(Payload.self) else { return }
        switch event.type {
        case "session.execution.started":
            status = .running
        case "session.step.started":
            status = .running
            if let model = payload.model { self.model = model }
        case "session.text.started":
            upsertText(payload.partID("text"), "")
        case "session.text.delta":
            guard let delta = payload.delta else { return }
            let id = payload.partID("text")
            upsertText(id, currentText(id) + delta)
        case "session.text.ended":
            upsertText(payload.partID("text"), payload.text ?? "")
        case "session.reasoning.started":
            updateReasoning(payload.partID("reasoning")) { $0.started = now }
        case "session.reasoning.delta":
            guard let delta = payload.delta else { return }
            updateReasoning(payload.partID("reasoning")) { $0.text += delta }
        case "session.reasoning.ended":
            updateReasoning(payload.partID("reasoning")) {
                $0.text = payload.text ?? $0.text
                $0.ended = now
            }
        case "session.tool.input.started":
            guard let id = payload.id else { return }
            updateTool(id) { $0.name = payload.name ?? $0.name }
        case "session.tool.called":
            guard let id = payload.id else { return }
            updateTool(id) { $0.subject = payload.input?.subject }
        case "session.tool.success":
            guard let id = payload.id else { return }
            updateTool(id) {
                $0.state = .succeeded
                $0.output = Self.clip(payload.content?.text)
            }
        case "session.tool.failed":
            guard let id = payload.id else { return }
            updateTool(id) {
                $0.state = .failed
                $0.output = Self.clip(payload.error?.message ?? payload.content?.text)
            }
        case "session.execution.succeeded":
            status = .succeeded
        case "session.execution.failed":
            status = .failed(payload.error?.message ?? "")
        case "session.execution.interrupted":
            status = .interrupted
        default:
            break
        }
    }

    static func clip(_ text: String?) -> String? {
        guard let text, text.count > maximumToolOutput else { return text }
        return String(text.prefix(maximumToolOutput)) + "\n…"
    }

    private func currentText(_ id: String) -> String {
        for case .text(id, let text) in parts { return text }
        return ""
    }

    private mutating func upsertText(_ id: String, _ text: String) {
        upsert(.text(id: id, text: text))
    }

    /// Creates the part when its `started` event was missed, e.g. after a reconnect.
    private mutating func updateReasoning(_ id: String, _ change: (inout Reasoning) -> Void) {
        var reasoning = Reasoning(id: id, text: "")
        if let index = parts.firstIndex(where: { $0.id == id }), case .reasoning(let existing) = parts[index] {
            reasoning = existing
        }
        change(&reasoning)
        upsert(.reasoning(reasoning))
    }

    private mutating func updateTool(_ id: String, _ change: (inout ToolCall) -> Void) {
        var call = ToolCall(id: id, name: "tool")
        if let index = parts.firstIndex(where: { $0.id == id }), case .tool(let existing) = parts[index] {
            call = existing
        }
        change(&call)
        upsert(.tool(call))
    }

    private mutating func upsert(_ part: Part) {
        if let index = parts.firstIndex(where: { $0.id == part.id }) {
            parts[index] = part
        } else {
            parts.append(part)
        }
    }

    private struct Payload: Decodable {
        struct ToolInput: Decodable {
            let query: String?
            let url: String?
            var subject: String? { query ?? url }
        }

        struct StructuredError: Decodable {
            let message: String
        }

        let assistantMessageID: String?
        let ordinal: Int?
        let delta: String?
        let text: String?
        let id: String?
        let name: String?
        let model: ModelRef?
        let input: ToolInput?
        let content: ToolContent?
        let error: StructuredError?

        func partID(_ kind: String) -> String {
            "\(assistantMessageID ?? "")/\(kind)/\(ordinal ?? 0)"
        }
    }
}

/// A tool result: a list of `{type, text}` items, of which only text is shown.
struct ToolContent: Decodable, Sendable {
    let text: String?

    private struct Item: Decodable {
        let type: String
        let text: String?
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            text = single
            return
        }
        let items = try decoder.singleValueContainer().decode([LenientItem].self)
        let texts = items.compactMap { $0.item?.text }
        text = texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }

    private struct LenientItem: Decodable {
        let item: Item?
        init(from decoder: Decoder) throws { item = try? Item(from: decoder) }
    }
}
