import Testing
import Foundation
@testable import FloatingChat

/// Talks to the real local background service. Run with:
/// `TEST_RUNNER_OCF_INTEGRATION=1 xcodebuild … test`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OCF_INTEGRATION"] == "1"))
struct OpenCodeIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func sessionRoundTrip() async throws {
        let service = try #require(ServiceDiscovery.read(), "opencode background service is not running")
        let client = OpenCodeClient(endpoint: OpenCodeEndpoint(service))

        #expect(try await !client.info().version.isEmpty)

        let directory = FileManager.default.temporaryDirectory.appending(path: "ocf-integration-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(try await !client.listModels(directory: directory).isEmpty)

        let session = try await client.createSession(CreateSessionRequest(
            location: .init(directory: directory),
            metadata: ["app": "opencode-floating", "purpose": "integration-test"],
            permissions: [PermissionRule(action: "*", resource: "*", effect: "deny")]
        ))
        defer { Task { try? await client.deleteSession(session.id) } }
        #expect(session.location.directory == directory)

        let listed = try await client.listSessions(directory: directory)
        #expect(listed.contains { $0.id == session.id })

        struct TextEnded: Decodable { let text: String }
        let collector = Task {
            var text = ""
            for try await event in client.events() where event.sessionID == session.id {
                if event.type == "session.text.ended" { text += try event.decodeData(TextEnded.self).text }
                if event.type.hasPrefix("session.execution."), event.type != "session.execution.started" { break }
            }
            return text
        }
        try await Task.sleep(for: .milliseconds(500))
        try await client.prompt(sessionID: session.id, PromptRequest(text: "Reply with exactly the word OK and nothing else."))

        let answer = try await collector.value
        #expect(answer.contains("OK"))
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func conversationAnswersThroughQuickAgent() async throws {
        try ScratchWorkspace.ensure()
        try QuickAgent.installIfMissing()
        let connection = ConnectionManager()
        connection.start()
        while connection.state != .connected { try await Task.sleep(for: .milliseconds(100)) }

        let defaults = try #require(UserDefaults(suiteName: "ocf-integration-\(UUID().uuidString)"))
        let conversation = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))
        conversation.send("Reply with exactly the word OK and nothing else.")
        #expect(conversation.isAnswering)
        while conversation.isAnswering { try await Task.sleep(for: .milliseconds(100)) }

        let sessionID = try #require(conversation.sessionID)
        let client = try #require(connection.client)
        defer { Task { try? await client.deleteSession(sessionID) } }
        let answer = try #require(conversation.turns.last?.answer)
        #expect(answer.status == .succeeded)
        #expect(answer.text.contains("OK"))
        #expect(answer.model != nil)

        // Finished while the panel was hidden: unread until viewed.
        #expect(conversation.hasUnreadAnswer)
        #expect(conversation.lastInteraction != nil)
        conversation.markViewed()
        var viewed = false
        for _ in 0..<30 where !viewed {
            try await Task.sleep(for: .milliseconds(100))
            viewed = try await !client.session(sessionID).hasUnreadAnswer
        }
        #expect(viewed)

        // Reopening rebuilds the same transcript from the server.
        let reopened = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))
        while reopened.turns.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(reopened.sessionID == sessionID)
        #expect(reopened.turns.map(\.question) == conversation.turns.map(\.question))
        #expect(reopened.turns.last?.answer.text == answer.text)
        #expect(reopened.turns.last?.answer.status == .succeeded)
        #expect(!reopened.hasUnreadAnswer)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func attachmentsAreSentStoredAndRegenerated() async throws {
        try ScratchWorkspace.ensure()
        try QuickAgent.installIfMissing()
        let connection = ConnectionManager()
        connection.start()
        while connection.state != .connected { try await Task.sleep(for: .milliseconds(100)) }
        let client = try #require(connection.client)
        let note = FileManager.default.temporaryDirectory.appending(path: "ocf-note-\(UUID().uuidString).txt")
        try Data("The secret word is PELICAN.".utf8).write(to: note)
        defer { try? FileManager.default.removeItem(at: note) }

        let defaults = try #require(UserDefaults(suiteName: "ocf-integration-\(UUID().uuidString)"))
        let conversation = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))
        let image = try #require(Attachment.image(AttachmentTests.pngData(width: 16, height: 16)))
        conversation.send("What is the secret word in the attached note? Reply with just the word.", attachments: [image, try #require(Attachment.file(note))])
        while conversation.isAnswering { try await Task.sleep(for: .milliseconds(100)) }
        let sessionID = try #require(conversation.sessionID)
        defer { Task { try? await client.deleteSession(sessionID) } }
        #expect(conversation.turns.last?.answer.text.uppercased().contains("PELICAN") == true)

        let history = ConversationHistory.turns(from: try await client.messages(sessionID: sessionID))
        #expect(history.last?.attachments.map(\.mime) == ["image/png", "text/plain"])

        // Regenerating resends the attachments even after the file is gone.
        let stored = try #require(history.last)
        try FileManager.default.removeItem(at: note)
        let reopened = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))
        while reopened.turns.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(reopened.turns.last?.attachments.count == stored.attachments.count)
        reopened.regenerate()
        while reopened.isAnswering { try await Task.sleep(for: .milliseconds(100)) }
        #expect(reopened.turns.last?.answer.text.uppercased().contains("PELICAN") == true)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func newSessionUsesPreferredModelAndSwitches() async throws {
        try ScratchWorkspace.ensure()
        try QuickAgent.installIfMissing()
        let connection = ConnectionManager()
        connection.start()
        while connection.state != .connected { try await Task.sleep(for: .milliseconds(100)) }
        let client = try #require(connection.client)
        let info = try await client.defaultModel(directory: ScratchWorkspace.path)
        let variants = info.variantIDs
        try #require(variants.count >= 2, "default model needs two variants for this test")
        let preferred = ModelRef(providerID: info.providerID, id: info.id, variant: variants[0])

        let defaults = try #require(UserDefaults(suiteName: "ocf-integration-\(UUID().uuidString)"))
        let conversation = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))
        conversation.newSessionModel = { preferred }
        conversation.send("Reply with exactly the word OK and nothing else.")
        while conversation.isAnswering { try await Task.sleep(for: .milliseconds(100)) }
        let sessionID = try #require(conversation.sessionID)
        defer { Task { try? await client.deleteSession(sessionID) } }
        #expect(conversation.model == preferred)
        #expect(try await client.session(sessionID).model == preferred)

        let switched = ModelRef(providerID: info.providerID, id: info.id, variant: variants[1])
        conversation.selectModel(switched)
        var serverModel: ModelRef?
        for _ in 0..<30 {
            serverModel = try await client.session(sessionID).model
            if serverModel == switched { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(serverModel == switched)
        #expect(conversation.model == switched)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func regenerateReplacesLastTurnAndStopInterrupts() async throws {
        try ScratchWorkspace.ensure()
        try QuickAgent.installIfMissing()
        let connection = ConnectionManager()
        connection.start()
        while connection.state != .connected { try await Task.sleep(for: .milliseconds(100)) }
        let defaults = try #require(UserDefaults(suiteName: "ocf-integration-\(UUID().uuidString)"))
        let conversation = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))

        conversation.send("Reply with exactly the word OK and nothing else.")
        while conversation.isAnswering { try await Task.sleep(for: .milliseconds(100)) }
        let sessionID = try #require(conversation.sessionID)
        let client = try #require(connection.client)
        defer { Task { try? await client.deleteSession(sessionID) } }
        let firstMessageID = try #require(conversation.turns.last?.messageID)
        #expect(conversation.canRegenerate)

        conversation.regenerate()
        #expect(conversation.isAnswering)
        while conversation.isAnswering { try await Task.sleep(for: .milliseconds(100)) }
        #expect(conversation.turns.count == 1)
        #expect(conversation.turns[0].answer.status == .succeeded)
        #expect(conversation.turns[0].messageID != firstMessageID)
        let users = try await client.messages(sessionID: sessionID).filter { if case .user = $0 { true } else { false } }
        #expect(users.count == 1)

        conversation.send("Count slowly from 1 to 300, one number per line.")
        while conversation.turns.last?.answer.text.isEmpty != false { try await Task.sleep(for: .milliseconds(100)) }
        conversation.stop()
        while conversation.isAnswering { try await Task.sleep(for: .milliseconds(100)) }
        #expect(conversation.turns.last?.answer.status == .interrupted)
    }

    @Test func quickAgentInScratchWorkspace() async throws {
        let service = try #require(ServiceDiscovery.read(), "opencode background service is not running")
        let client = OpenCodeClient(endpoint: OpenCodeEndpoint(service))
        try ScratchWorkspace.ensure()
        try QuickAgent.installIfMissing()

        let session = try await client.createSession(CreateSessionRequest(
            agent: QuickAgent.id,
            location: .init(directory: ScratchWorkspace.path),
            metadata: ["app": "opencode-floating", "purpose": "integration-test"]
        ))
        defer { Task { try? await client.deleteSession(session.id) } }
        #expect(session.agent == QuickAgent.id)
        #expect(session.location.directory == ScratchWorkspace.path)
        #expect(try await client.listSessions(directory: ScratchWorkspace.path).contains { $0.id == session.id })
    }
}
