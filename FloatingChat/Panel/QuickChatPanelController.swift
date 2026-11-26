import AppKit
import SwiftUI

@MainActor
final class QuickChatPanelController: NSObject, NSWindowDelegate {
    static let defaultWidth: CGFloat = 640

    let model: QuickChatModel

    private let panel: QuickChatPanel
    private let positions = PanelPositionStore(defaults: .standard)
    private let sizes = PanelSizeStore(defaults: .standard)
    private var keyMonitor: Any?
    private var heightBeforeLiveResize: CGFloat?
    private lazy var fieldEditor: QuickChatFieldEditor = {
        let editor = QuickChatFieldEditor()
        editor.isFieldEditor = true
        editor.receiver = self
        return editor
    }()

    init(connection: ConnectionManager) {
        model = QuickChatModel(connection: connection)
        let width = max(sizes.width ?? Self.defaultWidth, QuickChatLayout.minimumWidth)
        panel = QuickChatPanel(contentRect: CGRect(x: 0, y: 0, width: width, height: QuickChatLayout.inputBarHeight))
        super.init()
        let hostingView = QuickChatHostingView(rootView: QuickChatView(model: model))
        hostingView.sizingOptions = []
        hostingView.receiver = self
        panel.contentView = hostingView
        panel.minSize = CGSize(width: QuickChatLayout.minimumWidth, height: QuickChatLayout.inputBarHeight)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        model.onChooseFiles = { [weak self] in self?.chooseFiles() }
        model.onClose = { [weak self] in self?.hide() }
        installKeyMonitor()
        observeLayout()
    }

    var isVisible: Bool { panel.isVisible }

    /// Hidden → show. Visible but unfocused (it always floats) → focus. Focused → hide.
    func toggle() {
        if !panel.isVisible {
            show()
        } else if panel.isKeyWindow {
            hide()
        } else {
            focus()
        }
    }

    func show() {
        if !panel.isVisible {
            model.willSummon()
        }
        if let screen = NSScreen.underMouse {
            let saved = screen.displayUUID.flatMap(positions.topLeft(for:))
            var frame = PanelPlacement.frame(size: panel.frame.size, visibleFrame: screen.visibleFrame, savedTopLeft: saved)
            frame = PanelSizing.frame(current: frame, preferredHeight: model.preferredHeight, maximumHeight: sizes.maximumHeight, visibleFrame: screen.visibleFrame)
            panel.setFrame(frame, display: false)
        }
        focus()
    }

    func hide() {
        panel.orderOut(nil)
        model.didHide()
    }

    private func focus() {
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
        selectDraftWhenFocused()
    }

    /// Typing replaces the Draft; → continues editing it. SwiftUI applies focus
    /// asynchronously, so wait for the field editor to take over first.
    private func selectDraftWhenFocused() {
        Task { @MainActor [weak self] in
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(20))
                guard let self, self.panel.isKeyWindow else { return }
                if let editor = self.panel.firstResponder as? NSTextView, editor.isFieldEditor {
                    editor.selectAll(nil)
                    return
                }
            }
        }
    }

    // MARK: Sizing

    private func observeLayout() {
        withObservationTracking {
            _ = model.preferredHeight
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyPreferredHeight()
                self?.observeLayout()
            }
        }
    }

    private func applyPreferredHeight() {
        guard !panel.inLiveResize, let screen = panel.screen ?? NSScreen.underMouse else { return }
        let frame = PanelSizing.frame(
            current: panel.frame,
            preferredHeight: model.preferredHeight,
            maximumHeight: sizes.maximumHeight,
            visibleFrame: screen.visibleFrame
        )
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender.inLiveResize else { return frameSize }
        // Collapsed, the panel is just the input bar: only its width can change.
        let height = model.isExpanded ? max(frameSize.height, QuickChatLayout.minimumExpandedHeight) : sender.frame.height
        return NSSize(width: frameSize.width, height: height)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        heightBeforeLiveResize = panel.frame.height
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        sizes.width = panel.frame.width
        if model.isExpanded, let before = heightBeforeLiveResize, before != panel.frame.height {
            sizes.maximumHeight = panel.frame.height
        }
        heightBeforeLiveResize = nil
        applyPreferredHeight()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.isPanelKey = true
    }

    func windowDidResignKey(_ notification: Notification) {
        model.isPanelKey = false
    }

    func windowDidMove(_ notification: Notification) {
        guard let id = panel.screen?.displayUUID else { return }
        positions.save(CGPoint(x: panel.frame.minX, y: panel.frame.maxY), for: id)
    }

    // MARK: Attachments

    /// The app never activates for the panel, but an open panel needs to be frontmost to
    /// take the keyboard; the previously frontmost app is brought back afterwards.
    private func chooseFiles() {
        let previous = NSWorkspace.shared.frontmostApplication
        let chooser = NSOpenPanel()
        chooser.allowsMultipleSelection = true
        chooser.canChooseDirectories = false
        chooser.canChooseFiles = true
        chooser.level = .modalPanel
        NSApp.activate()
        chooser.begin { [weak self] response in
            guard let self else { return }
            if response == .OK {
                self.model.attach(chooser.urls.compactMap(Attachment.file))
            }
            if let previous, previous != NSRunningApplication.current {
                previous.activate()
            }
            self.panel.makeKeyAndOrderFront(nil)
            self.model.requestFocus()
        }
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        fieldEditor
    }

    // MARK: Keys

    private static let escapeKey: UInt16 = 53
    private static let tabKey: UInt16 = 48
    private static let deleteKey: UInt16 = 51
    private static let returnKeys: Set<UInt16> = [36, 76]
    private static let leftKey: UInt16 = 123
    private static let rightKey: UInt16 = 124
    private static let downKey: UInt16 = 125
    private static let upKey: UInt16 = 126

    /// The field editor swallows Esc before it reaches `cancelOperation`, a text field
    /// cannot tell Return from ⇧Return, and the accessory app has no main menu for ⌘N, ⌘W and ⌘.,
    /// so these are intercepted here.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            if self.model.picker != nil, let handled = self.handlePickerKey(event) {
                return handled ? nil : event
            }
            if self.model.recents != nil, let handled = self.handleRecentsKey(event) {
                return handled ? nil : event
            }
            if self.model.skillMenu != nil, let handled = self.handleSkillMenuKey(event) {
                return handled ? nil : event
            }
            if event.keyCode == Self.deleteKey, self.removeSkillOnDelete(event) {
                return nil
            }
            if event.keyCode == Self.escapeKey {
                self.hide()
                return nil
            }
            if Self.returnKeys.contains(event.keyCode) {
                return self.handleReturn(event)
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == .command, Self.isKey("k", keyCode: 40, event) {
                self.model.toggleRecents()
                return nil
            }
            if modifiers == .command, Self.isKey("n", keyCode: 45, event) {
                self.model.newConversation()
                return nil
            }
            if modifiers == .command, Self.isKey("w", keyCode: 13, event) {
                self.hide()
                return nil
            }
            // The text system would turn ⌘. into cancelOperation, which hides the panel.
            if modifiers == .command, Self.isKey(".", keyCode: 47, event) {
                self.model.stop()
                return nil
            }
            // The text view handles ⌘V itself, bypassing the field editor's paste(_:).
            if modifiers == .command, Self.isKey("v", keyCode: 9, event), self.model.picker == nil,
               self.attach(from: .general, isPaste: true) {
                return nil
            }
            return event
        }
    }

    /// Matches by character so other layouts (Dvorak) work, falling back to the ANSI key
    /// position when the layout yields no ASCII letter (e.g. Zhuyin).
    private static func isKey(_ character: String, keyCode: UInt16, _ event: NSEvent) -> Bool {
        guard let typed = event.charactersIgnoringModifiers?.lowercased(), typed.allSatisfy(\.isASCII) else {
            return event.keyCode == keyCode
        }
        return typed == character
    }

    /// Returns whether the model menu consumed the key, or `nil` when it does not apply.
    private func handlePickerKey(_ event: NSEvent) -> Bool? {
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        guard modifiers.isEmpty else { return nil }
        switch event.keyCode {
        case Self.escapeKey:
            model.pickerBack()
        case let key where Self.returnKeys.contains(key):
            model.activatePickerRow()
        case Self.upKey:
            model.movePickerHighlight(by: -1)
        case Self.downKey:
            model.movePickerHighlight(by: 1)
        // In the search field, → only means "open variants" when there is no text to move through.
        case Self.rightKey where model.picker?.query.isEmpty == true && model.picker?.highlightedHasVariants == true:
            model.activatePickerRow()
        case Self.leftKey where model.picker.map(Self.isVariantLevel) == true:
            model.pickerBack()
        default:
            return nil
        }
        return true
    }

    /// Returns whether the recent conversations menu consumed the key, or `nil` when it does not apply.
    private func handleRecentsKey(_ event: NSEvent) -> Bool? {
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        guard modifiers.isEmpty else { return nil }
        switch event.keyCode {
        case Self.escapeKey:
            model.closeRecents()
        case let key where Self.returnKeys.contains(key):
            model.activateRecent()
        case Self.upKey:
            model.moveRecentsHighlight(by: -1)
        case Self.downKey:
            model.moveRecentsHighlight(by: 1)
        default:
            return nil
        }
        return true
    }

    /// Returns whether the skill menu consumed the key, or `nil` when it does not apply.
    private func handleSkillMenuKey(_ event: NSEvent) -> Bool? {
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        guard modifiers.isEmpty else { return nil }
        switch event.keyCode {
        case Self.escapeKey:
            model.dismissSkillMenu()
        // With no match, Return falls through and sends the Draft as typed.
        case let key where Self.returnKeys.contains(key) || key == Self.tabKey:
            return model.activateSkill() ? true : (key == Self.tabKey ? true : nil)
        case Self.upKey:
            model.moveSkillHighlight(by: -1)
        case Self.downKey:
            model.moveSkillHighlight(by: 1)
        default:
            return nil
        }
        return true
    }

    /// ⌫ in an empty field removes the chosen skill, like deleting a token.
    private func removeSkillOnDelete(_ event: NSEvent) -> Bool {
        guard model.selectedSkill != nil, model.draft.isEmpty,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor, !editor.hasMarkedText()
        else { return false }
        model.removeSelectedSkill()
        return true
    }

    private static func isVariantLevel(_ picker: ModelPicker) -> Bool {
        if case .variants = picker.level { true } else { false }
    }

    private func handleReturn(_ event: NSEvent) -> NSEvent? {
        // Marked text means an input method (e.g. Zhuyin) is composing; Return commits it.
        guard let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor, !editor.hasMarkedText() else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .shift {
            editor.insertNewlineIgnoringFieldEditor(nil)
            return nil
        }
        guard modifiers.subtracting([.numericPad, .function]).isEmpty else { return event }
        model.submit()
        return nil
    }
}

extension QuickChatPanelController: AttachmentReceiver {
    func setPointerInside(_ inside: Bool) {
        model.isPointerInside = inside
    }

    func attach(from pasteboard: NSPasteboard, isPaste: Bool) -> Bool {
        model.attach(AttachmentPasteboard.attachments(from: pasteboard, isPaste: isPaste))
    }

    func setDropTargeted(_ targeted: Bool) {
        model.isDropTargeted = targeted
    }
}
