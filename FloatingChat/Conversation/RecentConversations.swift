import Foundation

/// The ⌘K menu: the latest Conversations in the Scratch Workspace, most recently updated
/// first. Like the model menu, it is shown in place of the transcript.
struct RecentConversations {
    static let limit = 20

    enum State {
        case loading
        case loaded([SessionInfo])
        case failed
    }

    /// The Conversation shown now; marked with a checkmark and highlighted once loaded.
    let currentID: String?
    private(set) var state = State.loading
    private(set) var highlighted = 0

    init(currentID: String?) {
        self.currentID = currentID
    }

    var sessions: [SessionInfo] {
        if case .loaded(let sessions) = state { sessions } else { [] }
    }

    mutating func load(_ sessions: [SessionInfo]) {
        state = .loaded(sessions)
        highlighted = sessions.firstIndex { $0.id == currentID } ?? 0
    }

    mutating func fail() {
        state = .failed
    }

    mutating func highlight(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        highlighted = index
    }

    mutating func move(by offset: Int) {
        guard !sessions.isEmpty else { return }
        highlighted = min(max(highlighted + offset, 0), sessions.count - 1)
    }

    var highlightedSession: SessionInfo? {
        sessions.indices.contains(highlighted) ? sessions[highlighted] : nil
    }
}
