import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class QuickChatModel {
    struct PreviousConversation: Equatable {
        let sessionID: String
        let lastInteraction: Date?
    }

    /// Belongs to Quick Chat, not to a Conversation: it survives Idle Reset and ⌘N.
    var draft = "" {
        didSet { updateSkillMenu() }
    }
    /// The skill chosen from the `/` menu; it is activated with the next question.
    private(set) var selectedSkill: SkillInfo?
    /// Open while the Draft is a `/` word; shown in place of the transcript.
    private(set) var skillMenu: SkillMenu?
    /// Files and images waiting to be sent with the Draft; like it, they survive Idle Reset.
    private(set) var attachments: [Attachment] = []
    var isDropTargeted = false
    /// Together these decide between the active and idle background opacity.
    var isPanelKey = false
    var isPointerInside = false
    private(set) var focusRequest = 0
    /// Set right after an Idle Reset, so the user can go back with one click.
    private(set) var previousConversation: PreviousConversation?
    let conversation: ConversationController
    let connection: ConnectionManager
    let models: ModelCatalog
    /// The open model menu, shown in place of the transcript.
    private(set) var picker: ModelPicker?
    /// The open ⌘K menu, also shown in place of the transcript.
    private(set) var recents: RecentConversations?

    /// Natural heights reported by the view; the panel controller sizes the window from them.
    var inputBarHeight: CGFloat = QuickChatLayout.inputBarHeight
    var transcriptHeight: CGFloat = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preferredModel: PreferredModelStore
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var recentsTask: Task<Void, Never>?
    @ObservationIgnored private var skillsTask: Task<Void, Never>?
    /// The last list fetched, shown at once the next time the menu opens.
    @ObservationIgnored private var cachedSkills: [SkillInfo]?
    /// Esc closed the menu; it stays closed until the Draft stops being a `/` word.
    @ObservationIgnored private var skillMenuDismissed = false

    init(connection: ConnectionManager, conversation: ConversationController? = nil, defaults: UserDefaults = .standard) {
        self.connection = connection
        self.conversation = conversation ?? ConversationController(connection: connection)
        models = ModelCatalog(connection: connection)
        self.defaults = defaults
        preferredModel = PreferredModelStore(defaults: defaults)
        self.conversation.newSessionModel = { [weak self] in self?.availablePreferredModel }
    }

    var isExpanded: Bool { !conversation.turns.isEmpty }

    var isPanelActive: Bool { isPanelKey || isPointerInside }

    var preferredHeight: CGFloat {
        let header = isExpanded ? QuickChatLayout.headerHeight : 0
        if picker != nil || recents != nil { return header + QuickChatLayout.pickerHeight + inputBarHeight }
        if let skillMenu { return header + QuickChatLayout.skillMenuHeight(rows: skillMenu.matches.count) + inputBarHeight }
        guard isExpanded else { return inputBarHeight }
        return header + transcriptHeight + inputBarHeight
    }

    /// The model the next answer will use.
    var currentModel: ModelRef? {
        if let model = conversation.model { return model }
        if conversation.sessionID == nil, let preferred = availablePreferredModel { return preferred }
        return models.defaultModel
    }

    var currentModelLabel: String? {
        guard let model = currentModel else { return nil }
        let name = models.displayName(for: model)
        guard let variant = model.variant else { return name }
        return "\(name) · \(variant)"
    }

    /// A Preferred Model that has since been removed falls back to the server default.
    private var availablePreferredModel: ModelRef? {
        guard let preferred = preferredModel.model, models.isAvailable(preferred) else { return nil }
        return preferred
    }

    // MARK: Model menu

    func toggleModelPicker() {
        if picker == nil { openModelPicker() } else { closeModelPicker() }
    }

    func openModelPicker() {
        guard !models.models.isEmpty else { return }
        closeRecents()
        dismissSkillMenu()
        picker = ModelPicker(models: models.models, current: currentModel)
    }

    func closeModelPicker() {
        guard picker != nil else { return }
        picker = nil
        requestFocus()
    }

    func setPickerQuery(_ query: String) {
        picker?.query = query
    }

    /// A click on a row.
    func choosePickerRow(_ index: Int) {
        picker?.highlight(index)
        activatePickerRow()
    }

    func movePickerHighlight(by offset: Int) {
        picker?.move(by: offset)
    }

    func activatePickerRow() {
        guard var picker else { return }
        if let choice = picker.activate() {
            chooseModel(choice)
        } else {
            self.picker = picker
        }
    }

    /// Esc: back to the model list from variants, otherwise close.
    func pickerBack() {
        guard var picker else { return }
        if picker.back() {
            self.picker = picker
        } else {
            closeModelPicker()
        }
    }

    /// Applies to the current Conversation and becomes the Preferred Model.
    func chooseModel(_ ref: ModelRef) {
        preferredModel.model = ref
        conversation.selectModel(ref)
        closeModelPicker()
    }

    // MARK: Recent Conversations

    func toggleRecents() {
        if recents == nil { openRecents() } else { closeRecents() }
    }

    func openRecents() {
        guard let client = connection.client else { return }
        picker = nil
        dismissSkillMenu()
        recents = RecentConversations(currentID: conversation.sessionID)
        recentsTask = Task { [weak self] in
            let sessions = try? await client.listSessions(directory: ScratchWorkspace.path, limit: RecentConversations.limit)
            guard !Task.isCancelled, let self, self.recents != nil else { return }
            if let sessions { self.recents?.load(sessions) } else { self.recents?.fail() }
        }
        requestFocus()
    }

    func closeRecents() {
        recentsTask?.cancel()
        recentsTask = nil
        guard recents != nil else { return }
        recents = nil
        requestFocus()
    }

    func moveRecentsHighlight(by offset: Int) {
        recents?.move(by: offset)
    }

    func activateRecent() {
        guard let session = recents?.highlightedSession else { return }
        openRecent(session)
    }

    func chooseRecent(_ index: Int) {
        recents?.highlight(index)
        activateRecent()
    }

    /// Resuming counts as an interaction, so the next Summon does not reset it right away.
    func openRecent(_ session: SessionInfo) {
        closeRecents()
        dismissNotice()
        guard session.id != conversation.sessionID else { return }
        conversation.open(sessionID: session.id, lastInteraction: .now)
    }

    // MARK: Skills

    private func updateSkillMenu() {
        guard let query = SkillMenu.query(in: draft) else {
            skillMenuDismissed = false
            closeSkillMenu()
            return
        }
        guard !skillMenuDismissed, picker == nil, recents == nil else { return }
        if skillMenu == nil {
            skillMenu = SkillMenu(state: cachedSkills.map { .loaded($0) } ?? .loading, query: query)
            loadSkills()
        } else {
            skillMenu?.setQuery(query)
        }
    }

    /// Refreshed every time the menu opens, since skills can be added at any time.
    private func loadSkills() {
        guard let client = connection.client else {
            skillMenu?.fail()
            return
        }
        skillsTask?.cancel()
        skillsTask = Task { [weak self] in
            let skills = try? await client.listSkills(directory: ScratchWorkspace.path)
            guard !Task.isCancelled, let self else { return }
            if let skills {
                self.cachedSkills = skills
                self.skillMenu?.load(skills)
            } else {
                self.skillMenu?.fail()
            }
        }
    }

    private func closeSkillMenu() {
        skillsTask?.cancel()
        skillsTask = nil
        skillMenu = nil
    }

    /// Esc: the `/` word stays as typed, to be sent as plain text.
    func dismissSkillMenu() {
        guard skillMenu != nil else { return }
        skillMenuDismissed = true
        closeSkillMenu()
    }

    func moveSkillHighlight(by offset: Int) {
        skillMenu?.move(by: offset)
    }

    /// Returns `false` when nothing matches, so Return sends the Draft instead.
    @discardableResult
    func activateSkill() -> Bool {
        guard let skill = skillMenu?.highlightedSkill else { return false }
        selectSkill(skill)
        return true
    }

    func chooseSkill(_ index: Int) {
        skillMenu?.highlight(index)
        activateSkill()
    }

    func selectSkill(_ skill: SkillInfo) {
        selectedSkill = skill
        draft = ""
        requestFocus()
    }

    func removeSelectedSkill() {
        selectedSkill = nil
        requestFocus()
    }

    func requestFocus() {
        focusRequest += 1
    }

    /// Called just before the panel appears. Idle Reset is only ever decided here, never
    /// while the panel stays open.
    func willSummon(now: Date = .now) {
        dismissNotice()
        if let sessionID = conversation.sessionID,
           IdleReset.shouldReset(
               lastInteraction: conversation.lastInteraction,
               now: now,
               threshold: IdleReset.threshold(defaults: defaults),
               hasUnreadAnswer: conversation.hasUnreadAnswer,
               isAnswering: conversation.isAnswering
           ) {
            let previous = PreviousConversation(sessionID: sessionID, lastInteraction: conversation.lastInteraction)
            conversation.startNew()
            showNotice(previous)
        }
        conversation.isPanelVisible = true
        if conversation.hasUnreadAnswer { conversation.markViewed() }
    }

    func didHide() {
        picker = nil
        closeRecents()
        conversation.isPanelVisible = false
    }

    var canSubmit: Bool {
        conversation.canSend
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || selectedSkill != nil)
            && !hasUnsupportedImages
    }

    func submit() {
        guard canSubmit else { return }
        dismissNotice()
        conversation.send(draft, attachments: attachments, skill: selectedSkill)
        draft = ""
        attachments = []
        selectedSkill = nil
    }

    // MARK: Attachments

    /// Returns `false` when there is nothing to attach, so a paste falls back to text.
    @discardableResult
    func attach(_ new: [Attachment]) -> Bool {
        guard picker == nil, !new.isEmpty else { return false }
        for attachment in new where !attachments.contains(where: { $0.isSameFile(as: attachment) }) {
            attachments.append(attachment)
        }
        requestFocus()
        return true
    }

    /// Opens the file chooser; set by the panel controller, which owns the window.
    @ObservationIgnored var onChooseFiles: (() -> Void)?

    func chooseFiles() {
        onChooseFiles?()
    }

    func removeAttachment(_ id: Attachment.ID) {
        attachments.removeAll { $0.id == id }
    }

    /// Unknown capabilities count as supported; the server reports a real mismatch anyway.
    var currentModelAcceptsImages: Bool {
        guard let model = currentModel, let input = models.info(for: model)?.capabilities?.input else { return true }
        return input.contains("image")
    }

    var hasUnsupportedImages: Bool {
        !currentModelAcceptsImages && attachments.contains(where: \.isImage)
    }

    func stop() {
        conversation.stop()
    }

    func regenerate() {
        conversation.regenerate()
    }

    func newConversation() {
        dismissNotice()
        closeRecents()
        guard !conversation.isEmpty else { return }
        conversation.startNew()
        requestFocus()
    }

    func returnToPreviousConversation() {
        guard let previous = previousConversation else { return }
        dismissNotice()
        conversation.open(sessionID: previous.sessionID, lastInteraction: previous.lastInteraction)
        requestFocus()
    }

    private func showNotice(_ previous: PreviousConversation) {
        previousConversation = previous
        noticeTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(8))) != nil else { return }
            self?.previousConversation = nil
        }
    }

    private func dismissNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        previousConversation = nil
    }
}

/// Only the background fades; text and controls stay fully opaque.
enum PanelOpacity {
    static let activeKey = "activeOpacity"
    static let idleKey = "idleOpacity"
    static let defaultActive = 0.95
    static let defaultIdle = 0.6
    static let range: ClosedRange<Double> = 0.2...1

    static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

enum QuickChatLayout {
    static let inputBarHeight: CGFloat = 60
    static let headerHeight: CGFloat = 32
    static let minimumWidth: CGFloat = 420
    static let minimumExpandedHeight: CGFloat = 160
    static let pickerHeight: CGFloat = 340

    /// Fits the matches, up to the height of the other menus.
    static func skillMenuHeight(rows: Int) -> CGFloat {
        min(max(CGFloat(rows) * 28 + 16, 64), pickerHeight)
    }
}
