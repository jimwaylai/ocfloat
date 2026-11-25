import Foundation

/// Rebuilds the transcript from a session's stored messages. One question is a `user`
/// message, followed by one `assistant` message per step and an `idle` message at the end.
enum ConversationHistory {
    static func turns(from messages: [SessionMessage]) -> [Turn] {
        var turns: [Turn] = []
        var pendingSkill: String?
        for message in messages {
            switch message {
            case .skill(let name):
                pendingSkill = name
            case .user(let id, let text, let files):
                let attachments = files.map { Attachment.stored(name: $0.name ?? "file", mime: $0.mime, data: $0.data) }
                turns.append(Turn(id: id, question: text, attachments: attachments, skill: pendingSkill, messageID: id, answer: Answer(status: .running)))
                pendingSkill = nil
            case .assistant(let id, let model, let content):
                guard let last = turns.indices.last else { continue }
                if let model { turns[last].answer.model = model }
                turns[last].answer.parts += parts(messageID: id, content: content)
            case .idle(let outcome, let errorMessage):
                guard let last = turns.indices.last else { continue }
                turns[last].answer.status = switch outcome {
                case "failed": .failed(errorMessage ?? "")
                case "interrupted": .interrupted
                default: .succeeded
                }
            case .other:
                continue
            }
        }
        return turns
    }

    /// Part IDs match the ones built from live events: ordinals count per kind within a message.
    private static func parts(messageID: String, content: [SessionMessage.AssistantContent]) -> [Answer.Part] {
        var textOrdinal = 0
        var reasoningOrdinal = 0
        return content.compactMap { item in
            switch item {
            case .text(let text):
                defer { textOrdinal += 1 }
                return .text(id: "\(messageID)/text/\(textOrdinal)", text: text)
            case .reasoning(let text, let started, let ended):
                defer { reasoningOrdinal += 1 }
                return .reasoning(.init(id: "\(messageID)/reasoning/\(reasoningOrdinal)", text: text, started: started, ended: ended))
            case .tool(let id, let name, let subject, let status, let output):
                let state: Answer.ToolCall.State = switch status {
                case "completed": .succeeded
                case "error": .failed
                default: .running
                }
                return .tool(.init(id: id, name: name, subject: subject, state: state, output: output))
            case .other:
                return nil
            }
        }
    }
}
