import Foundation

struct ModelRef: Codable, Hashable, Sendable {
    let providerID: String
    let id: String
    var variant: String?

    /// The same model, regardless of variant.
    func isSameModel(as other: ModelRef) -> Bool {
        providerID == other.providerID && id == other.id
    }
}

struct ServerInfo: Decodable, Sendable {
    let version: String
}

struct SessionInfo: Decodable, Identifiable, Sendable {
    struct Time: Decodable, Sendable {
        let created: Double
        let updated: Double
        let idle: Double?
        let viewed: Double?
    }

    struct Location: Decodable, Sendable {
        let directory: String
    }

    let id: String
    let title: String?
    let agent: String?
    let model: ModelRef?
    let outcome: String?
    let time: Time
    let location: Location

    /// An answer finished after the session was last viewed (here or in the TUI).
    var hasUnreadAnswer: Bool {
        guard let idle = time.idle else { return false }
        return idle > (time.viewed ?? 0)
    }
}

struct ModelInfo: Decodable, Identifiable, Sendable {
    struct Variant: Decodable, Sendable {
        let id: String
    }

    struct Capabilities: Decodable, Sendable {
        let input: [String]?
    }

    let id: String
    let providerID: String
    let name: String
    let variants: [Variant]?
    let capabilities: Capabilities?
    let enabled: Bool?

    var ref: ModelRef { ModelRef(providerID: providerID, id: id) }
    var variantIDs: [String] { variants?.map(\.id) ?? [] }
}

struct PermissionRule: Codable, Hashable, Sendable {
    let action: String
    let resource: String
    let effect: String
}

struct CreateSessionRequest: Encodable, Sendable {
    struct Location: Encodable, Sendable {
        let directory: String
    }

    var agent: String?
    var model: ModelRef?
    var location: Location
    var metadata: [String: String]?
    var permissions: [PermissionRule]?
}

struct PromptFile: Encodable, Sendable {
    struct Source: Encodable, Sendable {
        let type: String
    }

    let uri: String
    var name: String?
    var source: Source?
}

struct PromptRequest: Encodable, Sendable {
    let text: String
    var files: [PromptFile]?
}

/// An entry of `GET /api/skill`. The body is left out: the server injects it when the
/// skill is activated.
struct SkillInfo: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String?
}

struct DataEnvelope<Value: Decodable>: Decodable {
    let data: Value
}
