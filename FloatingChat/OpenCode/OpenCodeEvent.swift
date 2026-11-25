import Foundation

/// One event from the server's global stream. The stream carries every directory and
/// session, so consumers filter by `sessionID`.
struct OpenCodeEvent: Sendable {
    let id: String?
    let type: String
    let sessionID: String?
    let raw: Data

    init(json: Data) throws {
        let head = try JSONDecoder().decode(Head.self, from: json)
        id = head.id
        type = head.type
        sessionID = head.sessionID
        raw = json
    }

    func decodeData<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(DataEnvelope<Value>.self, from: raw).data
    }

    private struct Head: Decodable {
        let id: String?
        let type: String
        let sessionID: String?

        private enum CodingKeys: String, CodingKey { case id, type, data }
        private struct SessionRef: Decodable { let sessionID: String? }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            type = try container.decode(String.self, forKey: .type)
            sessionID = (try? container.decodeIfPresent(SessionRef.self, forKey: .data))??.sessionID
        }
    }
}
