import Testing
import AppKit
import UniformTypeIdentifiers
@testable import FloatingChat

struct AttachmentTests {
    static func pngData(width: Int, height: Int) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        image.addRepresentation(rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private static func pixelSize(_ data: Data) throws -> Int {
        let rep = try #require(NSBitmapImageRep(data: data))
        return max(rep.pixelsWide, rep.pixelsHigh)
    }

    @Test func smallPNGIsSentUnchangedWithThumbnail() throws {
        let png = try Self.pngData(width: 300, height: 200)
        let attachment = try #require(Attachment.image(png))
        #expect(attachment.source == .inline(png))
        #expect(attachment.mime == "image/png")
        #expect(try Self.pixelSize(#require(attachment.thumbnail)) == Attachment.thumbnailSize)
        #expect(attachment.promptFile.uri == "data:image/png;base64,\(png.base64EncodedString())")
        #expect(attachment.promptFile.source?.type == "inline")
    }

    @Test func largeOrNonPNGImagesBecomeBoundedPNG() throws {
        let png = try Self.pngData(width: 3000, height: 1000)
        let tiff = try #require(NSBitmapImageRep(data: png)?.tiffRepresentation)
        let attachment = try #require(Attachment.image(tiff))
        guard case .inline(let data) = attachment.source else { Issue.record("not inline"); return }
        #expect(NSBitmapImageRep(data: data) != nil)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(try Self.pixelSize(data) == Attachment.maximumImageSize)
    }

    @Test func notAnImageIsRejected() {
        #expect(Attachment.image(Data("hello".utf8)) == nil)
    }

    @Test func fileKeepsItsURLAndType() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ocf-attach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = directory.appending(path: "note.txt")
        try Data("hi".utf8).write(to: note)
        let picture = directory.appending(path: "red.png")
        try Self.pngData(width: 10, height: 10).write(to: picture)

        let file = try #require(Attachment.file(note))
        #expect(file.name == "note.txt")
        #expect(file.mime == "text/plain")
        #expect(file.thumbnail == nil)
        #expect(file.promptFile.uri == note.absoluteString)
        #expect(file.promptFile.source == nil)

        let image = try #require(Attachment.file(picture))
        #expect(image.isImage)
        #expect(image.thumbnail != nil)
        #expect(Attachment.file(directory) == nil)
        #expect(file.isSameFile(as: try #require(Attachment.file(note))))
        #expect(!file.isSameFile(as: image))
    }

    @Test func pasteboardRules() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ocf-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let png = try Self.pngData(width: 20, height: 20)

        pasteboard.clearContents()
        pasteboard.setString("just text", forType: .string)
        #expect(AttachmentPasteboard.attachments(from: pasteboard, isPaste: true).isEmpty)
        #expect(!AttachmentPasteboard.canAttach(from: pasteboard))

        // Rich text from many apps carries a rendered image too: text wins on paste.
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .png], owner: nil)
        pasteboard.setString("cell", forType: .string)
        pasteboard.setData(png, forType: .png)
        #expect(AttachmentPasteboard.attachments(from: pasteboard, isPaste: true).isEmpty)
        #expect(AttachmentPasteboard.attachments(from: pasteboard, isPaste: false).count == 1)

        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        #expect(AttachmentPasteboard.attachments(from: pasteboard, isPaste: true).map(\.mime) == ["image/png"])

        // A file copied in Finder also carries its path as text and its icon as an image.
        let url = FileManager.default.temporaryDirectory.appending(path: "ocf-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.path, forType: .string)
        #expect(AttachmentPasteboard.canAttach(from: pasteboard))
        #expect(AttachmentPasteboard.attachments(from: pasteboard, isPaste: true).map(\.name) == [url.lastPathComponent])
    }

    @Test func historyRestoresAttachments() throws {
        let png = try Self.pngData(width: 8, height: 8)
        let json = #"""
        {"data":[
          {"id":"msg_u","type":"user","text":"","files":[
            {"data":"\#(png.base64EncodedString())","mime":"image/png","source":{"type":"inline"},"name":"pasted.png"},
            {"data":"aGk=","mime":"text/plain","source":{"type":"uri","uri":"file:///tmp/note.txt"},"name":"note.txt"},
            {"broken":true}
          ]},
          {"id":"msg_i","type":"idle","outcome":"succeeded"}
        ]}
        """#
        let messages = try JSONDecoder().decode(DataEnvelope<LenientList<SessionMessage>>.self, from: Data(json.utf8)).data.elements
        let turn = try #require(ConversationHistory.turns(from: messages).first)
        #expect(turn.question == "")
        #expect(turn.attachments.map(\.name) == ["pasted.png", "note.txt"])
        #expect(turn.attachments[0].thumbnail != nil)
        #expect(turn.attachments[1].source == .inline(Data("hi".utf8)))
        #expect(turn.attachments[1].promptFile.uri == "data:text/plain;base64,aGk=")
    }
}

@MainActor
struct DraftAttachmentTests {
    private func makeModel() throws -> QuickChatModel {
        let defaults = try #require(UserDefaults(suiteName: "ocf-attach-\(UUID().uuidString)"))
        let connection = ConnectionManager(defaults: defaults)
        let conversation = ConversationController(connection: connection, store: ConversationStore(defaults: defaults))
        return QuickChatModel(connection: connection, conversation: conversation, defaults: defaults)
    }

    @Test func attachSkipsDuplicateFilesAndRemoves() throws {
        let model = try makeModel()
        let url = URL(fileURLWithPath: "/tmp/ocf-note.txt")
        let first = try #require(Attachment.file(url))
        #expect(!model.attach([]))
        #expect(model.attach([first]))
        #expect(model.attach([try #require(Attachment.file(url))]))
        #expect(model.attachments.count == 1)
        model.removeAttachment(first.id)
        #expect(model.attachments.isEmpty)
    }

    @Test func attachmentsSurviveNewConversation() throws {
        let model = try makeModel()
        model.attach([try #require(Attachment.image(AttachmentTests.pngData(width: 4, height: 4)))])
        model.newConversation()
        model.willSummon()
        #expect(model.attachments.count == 1)
    }
}
