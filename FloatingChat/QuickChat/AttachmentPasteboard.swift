import AppKit

/// Reads attachments from a paste or a drop: copied or dragged files, or image data such
/// as a screenshot.
enum AttachmentPasteboard {
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")]

    static var draggedTypes: [NSPasteboard.PasteboardType] { [.fileURL] + imageTypes }

    /// A cheap check for drag feedback, without reading the data.
    static func canAttach(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.availableType(from: imageTypes) != nil
    }

    /// Empty when the pasteboard holds nothing to attach. For a paste, text wins over an
    /// image: rich text copied from many apps carries a rendered image of itself too.
    static func attachments(from pasteboard: NSPasteboard, isPaste: Bool) -> [Attachment] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            return urls.compactMap(Attachment.file)
        }
        if isPaste, pasteboard.availableType(from: [.string]) != nil {
            return []
        }
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), let image = Attachment.image(data) {
                return [image]
            }
        }
        return []
    }
}
