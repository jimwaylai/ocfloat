import Foundation
import Observation

struct Turn: Identifiable, Equatable, Sendable {
    let id: String
    let question: String
    var attachments: [Attachment]
    /// The name of the skill activated with the question.
    var skill: String?
    /// The user message on the server; `nil` until the prompt is accepted.
    var messageID: String?
    var answer = Answer()

    init(id: String = UUID().uuidString, question: String, attachments: [Attachment] = [], skill: String? = nil, messageID: String? = nil, answer: Answer = Answer()) {
        self.id = id
        self.question = question
        self.attachments = attachments
        self.skill = skill
        self.messageID = messageID
        self.answer = answer
    }
}

/// The current Conversation: an opencode session in the Scratch Workspace, created lazily
/// on the first question and run with the Quick Agent. Which session is current, and when
/// it was last used, is persisted across launches.
@MainActor
@Observable
final class ConversationController {
    private(set) var sessionID: String?
    private(set) var title: String?
    private(set) var turns: [Turn] = []
    /// The later of the last question sent and the last answer finished.
    private(set) var lastInteraction: Date?
    private(set) var hasUnreadAnswer = false
    /// The session's own model. `nil` means the server default for an existing session, and
    /// `newSessionModel` for one that is not created yet.
    private(set) var model: ModelRef?

    /// The model a new session is created with: the Preferred Model.
    @ObservationIgnored var newSessionModel: @MainActor () -> ModelRef? = { nil }

    /// Answers that finish while the panel is visible count as read.
    var isPanelVisible = false

    @ObservationIgnored private let connection: ConnectionManager
    @ObservationIgnored private let store: ConversationStore
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init(connection: ConnectionManager, store: ConversationStore = ConversationStore(defaults: .standard)) {
        self.connection = connection
        self.store = store
        sessionID = store.sessionID
        lastInteraction = store.lastInteraction
        let events = connection.events()
        eventTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
        if sessionID != nil, connection.state == .connected {
            Task { await refresh() }
        }
    }

    var isAnswering: Bool { turns.last?.answer.isActive ?? false }

    var canSend: Bool { connection.state == .connected && !isAnswering }

    var isEmpty: Bool { sessionID == nil && turns.isEmpty }

    /// Leaves the current session untouched on the server; the next question creates a new one.
    func startNew() {
        switchTo(sessionID: nil, lastInteraction: nil)
    }

    func open(sessionID: String, lastInteraction: Date?) {
        switchTo(sessionID: sessionID, lastInteraction: lastInteraction)
        Task { await refresh() }
    }

    func send(_ text: String, attachments: [Attachment] = [], skill: SkillInfo? = nil) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || !attachments.isEmpty || skill != nil, canSend, let client = connection.client else { return }
        let turn = Turn(question: question, attachments: attachments, skill: skill?.name)
        turns.append(turn)
        touch()
        Task {
            do {
                let sessionID = try await ensureSession(client)
                if let skill {
                    try await client.activateSkill(sessionID: sessionID, id: skill.id)
                }
                try await prompt(turn, in: sessionID, client: client)
            } catch {
                fail(with: error)
            }
        }
    }

    var canRegenerate: Bool {
        canSend && turns.last?.messageID != nil
    }

    /// Asks the last question again: the old question and answer are removed from the
    /// session first, so the model does not see them.
    func regenerate() {
        guard canRegenerate, let sessionID, let client = connection.client,
              let last = turns.indices.last, let messageID = turns[last].messageID
        else { return }
        // The skill message comes before the question, so it stays in the session.
        let turn = Turn(question: turns[last].question, attachments: turns[last].attachments, skill: turns[last].skill)
        turns[last] = turn
        touch()
        Task {
            do {
                try await client.revert(sessionID: sessionID, from: messageID)
                try await prompt(turn, in: sessionID, client: client)
            } catch {
                fail(with: error)
            }
        }
    }

    /// Applies from the next step, even mid-answer.
    func selectModel(_ ref: ModelRef) {
        model = ref
        guard let sessionID, let client = connection.client else { return }
        Task {
            do {
                try await client.selectModel(sessionID: sessionID, ref)
            } catch {
                if let session = try? await client.session(sessionID), self.sessionID == sessionID {
                    model = session.model
                }
            }
        }
    }

    func stop() {
        guard isAnswering, let sessionID, let client = connection.client else { return }
        Task { try? await client.interrupt(sessionID: sessionID) }
    }

    private func prompt(_ turn: Turn, in sessionID: String, client: OpenCodeClient) async throws {
        let messageID = try await client.prompt(sessionID: sessionID, PromptRequest(
            text: turn.question,
            files: turn.attachments.isEmpty ? nil : turn.attachments.map(\.promptFile)
        ))
        if let index = turns.firstIndex(where: { $0.id == turn.id }) {
            turns[index].messageID = messageID
        }
    }

    /// Clears the Unread Answer on the server, which the TUI shares.
    func markViewed() {
        guard let sessionID, let client = connection.client else { return }
        hasUnreadAnswer = false
        Task {
            // `time.idle` can trail the completion event slightly.
            for attempt in 0..<3 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(400)) }
                guard let info = try? await client.session(sessionID), let idle = info.time.idle else { continue }
                if info.hasUnreadAnswer { try? await client.markViewed(sessionID: sessionID, idle: idle) }
                return
            }
        }
    }

    private func switchTo(sessionID: String?, lastInteraction: Date?) {
        self.sessionID = sessionID
        self.lastInteraction = lastInteraction
        title = nil
        model = nil
        turns = []
        hasUnreadAnswer = false
        store.sessionID = sessionID
        store.lastInteraction = lastInteraction
    }

    private func touch() {
        lastInteraction = .now
        store.lastInteraction = lastInteraction
    }

    private func ensureSession(_ client: OpenCodeClient) async throws -> String {
        if let sessionID { return sessionID }
        let model = model ?? newSessionModel()
        let session = try await client.createSession(CreateSessionRequest(
            agent: QuickAgent.id,
            model: model,
            location: .init(directory: ScratchWorkspace.path),
            metadata: ["app": "opencode-floating"]
        ))
        sessionID = session.id
        title = session.title
        self.model = session.model ?? model
        store.sessionID = session.id
        return session.id
    }

    /// Reloads the transcript from the server: on launch, when reopening a Conversation, and
    /// after a reconnect, since events emitted while disconnected are lost.
    private func refresh() async {
        guard let sessionID, let client = connection.client else { return }
        do {
            async let info = client.session(sessionID)
            async let messages = client.messages(sessionID: sessionID)
            let (session, history) = try await (info, messages)
            guard self.sessionID == sessionID else { return }
            title = session.title
            model = session.model
            turns = ConversationHistory.turns(from: history)
            if lastInteraction == nil {
                lastInteraction = Date(timeIntervalSince1970: session.time.updated / 1000)
                store.lastInteraction = lastInteraction
            }
            if session.hasUnreadAnswer {
                if isPanelVisible { markViewed() } else { hasUnreadAnswer = true }
            }
        } catch OpenCodeError.http(404, _) {
            // Deleted elsewhere, e.g. from the TUI.
            if self.sessionID == sessionID { startNew() }
        } catch {
            // Keep what is shown; the next reconnect retries.
        }
    }

    private func handle(_ event: OpenCodeEvent) {
        if event.type == "server.connected" {
            if sessionID != nil { Task { await refresh() } }
            return
        }
        guard let sessionID, event.sessionID == sessionID else { return }
        if event.type == "session.renamed", let renamed = try? event.decodeData(Renamed.self) {
            title = renamed.title
        }
        // Also covers switches made in the TUI.
        if event.type == "session.model.selected", let selected = try? event.decodeData(ModelSelected.self) {
            model = selected.model
        }
        guard let last = turns.indices.last, turns[last].answer.isActive else { return }
        turns[last].answer.apply(event)
        if !turns[last].answer.isActive { answerFinished() }
    }

    private func answerFinished() {
        touch()
        if isPanelVisible { markViewed() } else { hasUnreadAnswer = true }
    }

    private func fail(with error: Error) {
        guard let last = turns.indices.last, turns[last].answer.isActive else { return }
        turns[last].answer.status = .failed(Self.message(for: error))
    }

    private static func message(for error: Error) -> String {
        switch error {
        case OpenCodeError.unauthorized:
            String(localized: "opencode rejected the password.")
        case OpenCodeError.http(let status, let body):
            "HTTP \(status): \(body)"
        default:
            error.localizedDescription
        }
    }

    private struct Renamed: Decodable {
        let title: String
    }

    private struct ModelSelected: Decodable {
        let model: ModelRef
    }
}
