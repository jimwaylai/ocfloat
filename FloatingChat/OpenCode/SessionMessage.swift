import Foundation

/// One entry of `GET /api/session/{id}/message`. Only the types the transcript needs are
/// decoded; everything else (model switches, compaction …) becomes `.other`.
enum SessionMessage: Decodable, Sendable {
    case user(id: String, text: String, files: [StoredFile])
    case assistant(id: String, model: ModelRef?, content: [AssistantContent])
    case idle(outcome: String?, errorMessage: String?)
    /// A skill activated just before a question.
    case skill(name: String)
    case other

    enum AssistantContent: Decodable, Sendable {
        case text(String)
        case reasoning(String, started: Date?, ended: Date?)
        case tool(id: String, name: String, subject: String?, status: String?, output: String?)
        case other

        private enum CodingKeys: String, CodingKey { case type, text, id, name, state, time }

        private struct ToolState: Decodable {
            struct Input: Decodable {
                let query: String?
                let url: String?
            }

            struct StructuredError: Decodable {
                let message: String
            }

            let status: String?
            let input: Input?
            let content: ToolContent?
            let error: StructuredError?
        }

        private struct Time: Decodable {
            let created: Double?
            let completed: Double?
        }

        private static func date(_ milliseconds: Double?) -> Date? {
            milliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "text":
                self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
            case "reasoning":
                let time = try? container.decodeIfPresent(Time.self, forKey: .time)
                self = .reasoning(
                    try container.decodeIfPresent(String.self, forKey: .text) ?? "",
                    started: Self.date(time?.created),
                    ended: Self.date(time?.completed)
                )
            case "tool":
                let state = try? container.decodeIfPresent(ToolState.self, forKey: .state)
                self = .tool(
                    id: try container.decode(String.self, forKey: .id),
                    name: try container.decodeIfPresent(String.self, forKey: .name) ?? "tool",
                    subject: state?.input?.query ?? state?.input?.url,
                    status: state?.status,
                    output: Answer.clip(state?.error?.message ?? state?.content?.text)
                )
            default:
                self = .other
            }
        }
    }

    /// An attachment as stored by the server: its content is always inline.
    struct StoredFile: Decodable, Sendable {
        let name: String?
        let mime: String
        let data: Data
    }

    private enum CodingKeys: String, CodingKey { case type, id, text, files, model, content, outcome, error, skill, name }

    private struct StructuredError: Decodable {
        let message: String
    }

    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "user":
            self = .user(
                id: try container.decode(String.self, forKey: .id),
                text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
                files: (try? container.decodeIfPresent([Lenient<StoredFile>].self, forKey: .files))?.compactMap(\.value) ?? []
            )
        case "assistant":
            let content = try container.decodeIfPresent([Lenient<AssistantContent>].self, forKey: .content) ?? []
            self = .assistant(
                id: try container.decode(String.self, forKey: .id),
                model: try? container.decodeIfPresent(ModelRef.self, forKey: .model),
                content: content.map { $0.value ?? .other }
            )
        case "skill":
            self = .skill(name: try container.decodeIfPresent(String.self, forKey: .name)
                ?? container.decode(String.self, forKey: .skill))
        case "idle":
            self = .idle(
                outcome: try container.decodeIfPresent(String.self, forKey: .outcome),
                errorMessage: (try? container.decodeIfPresent(StructuredError.self, forKey: .error))?.message
            )
        default:
            self = .other
        }
    }
}

/// Decodes a list without letting one malformed entry fail the whole response.
struct LenientList<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else if (try? container.decode(Skip.self)) == nil {
                break
            }
        }
        self.elements = elements
    }

    private struct Skip: Decodable {}
}
