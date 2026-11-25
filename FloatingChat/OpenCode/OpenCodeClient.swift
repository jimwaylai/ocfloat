import Foundation

enum OpenCodeError: Error, Equatable {
    case unauthorized
    case http(status: Int, body: String)
    case invalidResponse
}

/// Thin client for the opencode server API. See `docs/opencode-api-notes.md`.
struct OpenCodeClient: Sendable {
    let endpoint: OpenCodeEndpoint
    var session: URLSession = .shared

    private static let streamingSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = .infinity
        return URLSession(configuration: configuration)
    }()

    func info() async throws -> ServerInfo {
        try await send(endpoint.request("GET", "/api/info"))
    }

    func createSession(_ body: CreateSessionRequest) async throws -> SessionInfo {
        try await send(endpoint.request("POST", "/api/session", body: encode(body)), as: DataEnvelope<SessionInfo>.self).data
    }

    func listSessions(directory: String, limit: Int = 20) async throws -> [SessionInfo] {
        let query = [
            URLQueryItem(name: "directory", value: directory),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await send(endpoint.request("GET", "/api/session", query: query), as: DataEnvelope<[SessionInfo]>.self).data
    }

    func session(_ sessionID: String) async throws -> SessionInfo {
        try await send(endpoint.request("GET", "/api/session/\(sessionID)"), as: DataEnvelope<SessionInfo>.self).data
    }

    /// The newest `limit` messages, oldest first. Quick Chat conversations are short, so
    /// one page is enough.
    func messages(sessionID: String, limit: Int = 200) async throws -> [SessionMessage] {
        let query = [URLQueryItem(name: "order", value: "desc"), URLQueryItem(name: "limit", value: String(limit))]
        let request = endpoint.request("GET", "/api/session/\(sessionID)/message", query: query)
        return try await send(request, as: DataEnvelope<LenientList<SessionMessage>>.self).data.elements.reversed()
    }

    /// Marks the answer that finished at `idle` (the session's `time.idle`) as read.
    func markViewed(sessionID: String, idle: Double) async throws {
        try await sendIgnoringBody(endpoint.request("POST", "/api/session/\(sessionID)/view", body: encode(["idle": idle])))
    }

    func deleteSession(_ sessionID: String) async throws {
        try await sendIgnoringBody(endpoint.request("DELETE", "/api/session/\(sessionID)"))
    }

    /// Asynchronous: returns the queued user message's ID; progress arrives on the event stream.
    @discardableResult
    func prompt(sessionID: String, _ body: PromptRequest) async throws -> String {
        try await send(endpoint.request("POST", "/api/session/\(sessionID)/prompt", body: encode(body)), as: DataEnvelope<Identified>.self).data.id
    }

    /// Permanently removes `messageID` and everything after it, so the question can be asked again.
    func revert(sessionID: String, from messageID: String) async throws {
        try await sendIgnoringBody(endpoint.request("POST", "/api/session/\(sessionID)/revert/stage", body: encode(["messageID": messageID])))
        try await sendIgnoringBody(endpoint.request("POST", "/api/session/\(sessionID)/revert/commit"))
    }

    /// Takes effect from the next step; the server confirms with `session.model.selected`.
    func selectModel(sessionID: String, _ model: ModelRef) async throws {
        try await sendIgnoringBody(endpoint.request("POST", "/api/session/\(sessionID)/model", body: encode(["model": model])))
    }

    func listSkills(directory: String) async throws -> [SkillInfo] {
        let request = endpoint.request("GET", "/api/skill", location: directory)
        return try await send(request, as: DataEnvelope<LenientList<SkillInfo>>.self).data.elements
    }

    /// Adds the skill's instructions to the session as a message of its own, without
    /// running the agent: the next prompt then follows them. The agent needs no skill tool.
    func activateSkill(sessionID: String, id: String) async throws {
        struct Body: Encodable {
            let id: String
            let resume: Bool
        }
        try await sendIgnoringBody(endpoint.request("POST", "/api/experimental/session/\(sessionID)/skill", body: encode(Body(id: id, resume: false))))
    }

    func interrupt(sessionID: String) async throws {
        try await sendIgnoringBody(endpoint.request("POST", "/api/session/\(sessionID)/interrupt"))
    }

    /// The first request for a location the server has not loaded yet returns an empty list
    /// while the model registry warms up, so empty results are retried briefly.
    func listModels(directory: String, attempts: Int = 6) async throws -> [ModelInfo] {
        let request = endpoint.request("GET", "/api/model", query: [URLQueryItem(name: "types", value: "chat")], location: directory)
        for attempt in 1...max(attempts, 1) {
            let models = try await send(request, as: DataEnvelope<[ModelInfo]>.self).data
            if !models.isEmpty || attempt == attempts { return models }
            try await Task.sleep(for: .milliseconds(300))
        }
        return []
    }

    /// The model sessions use when none is chosen.
    func defaultModel(directory: String) async throws -> ModelInfo {
        try await send(endpoint.request("GET", "/api/model/default", location: directory), as: DataEnvelope<ModelInfo>.self).data
    }

    /// One connection to the global event stream. It finishes, normally or by throwing,
    /// when the connection drops; reconnecting is the caller's job.
    func events() -> AsyncThrowingStream<OpenCodeEvent, Error> {
        let request = endpoint.request("GET", "/api/event", accept: "text/event-stream")
        let session = Self.streamingSession
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.check(response, body: Data())
                    var parser = SSEParser()
                    for try await byte in bytes {
                        if let payload = parser.push(byte), let event = try? OpenCodeEvent(json: Data(payload.utf8)) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct Identified: Decodable {
        let id: String
    }

    private func send<Value: Decodable>(_ request: URLRequest, as type: Value.Type = Value.self) async throws -> Value {
        let (data, response) = try await session.data(for: request)
        try Self.check(response, body: data)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func sendIgnoringBody(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        try Self.check(response, body: data)
    }

    private func encode(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OpenCodeError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw OpenCodeError.unauthorized
        default: throw OpenCodeError.http(status: http.statusCode, body: String(decoding: body, as: UTF8.self))
        }
    }
}
