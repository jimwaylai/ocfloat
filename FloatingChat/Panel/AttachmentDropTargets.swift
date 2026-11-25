import AppKit
import SwiftUI

/// Receives pasted and dropped attachments for the panel.
@MainActor
protocol AttachmentReceiver: AnyObject {
    /// Returns `false` when there is nothing to attach, so the default behavior applies.
    func attach(from pasteboard: NSPasteboard, isPaste: Bool) -> Bool
    func setDropTargeted(_ targeted: Bool)
    func setPointerInside(_ inside: Bool)
}

/// The panel's field editor. The default one pastes a copied file as its path and
/// inserts dropped files as text, so files and images are turned into attachments here.
final class QuickChatFieldEditor: NSTextView {
    weak var receiver: AttachmentReceiver?

    override func paste(_ sender: Any?) {
        if receiver?.attach(from: .general, isPaste: true) == true { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard AttachmentPasteboard.canAttach(from: sender.draggingPasteboard) else { return super.draggingEntered(sender) }
        receiver?.setDropTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard AttachmentPasteboard.canAttach(from: sender.draggingPasteboard) else { return super.draggingUpdated(sender) }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        receiver?.setDropTargeted(false)
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard AttachmentPasteboard.canAttach(from: sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        receiver?.setDropTargeted(false)
        return receiver?.attach(from: sender.draggingPasteboard, isPaste: false) ?? false
    }
}

/// Accepts files and images dropped anywhere else on the panel, and reports the pointer
/// entering and leaving even while the panel is not key.
final class QuickChatHostingView: NSHostingView<QuickChatView> {
    weak var receiver: AttachmentReceiver?

    /// The hidden title bar would otherwise inset the content, and the hosting view would
    /// grow the window by that inset, leaving empty space above or below the input.
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self && $0.userInfo?["pointer"] != nil }) {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: ["pointer": true]))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea?.userInfo?["pointer"] != nil { receiver?.setPointerInside(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea?.userInfo?["pointer"] != nil { receiver?.setPointerInside(false) }
    }

    required init(rootView: QuickChatView) {
        super.init(rootView: rootView)
        registerForDraggedTypes(AttachmentPasteboard.draggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard AttachmentPasteboard.canAttach(from: sender.draggingPasteboard) else { return [] }
        receiver?.setDropTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        AttachmentPasteboard.canAttach(from: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        receiver?.setDropTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        receiver?.setDropTargeted(false)
        return receiver?.attach(from: sender.draggingPasteboard, isPaste: false) ?? false
    }
}
