import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A file or image sent along with a question.
struct Attachment: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// The server reads the file itself when the question is sent.
        case file(URL)
        case inline(Data)
    }

    let id: UUID
    let name: String
    let mime: String
    let source: Source
    /// A small PNG for images, made once so the views stay cheap.
    let thumbnail: Data?

    /// Pasted images larger than this, in pixels on the longest side, are scaled down.
    static let maximumImageSize = 2048
    static let thumbnailSize = 240

    init(name: String, mime: String, source: Source, thumbnail: Data?) {
        id = UUID()
        self.name = name
        self.mime = mime
        self.source = source
        self.thumbnail = thumbnail
    }

    var isImage: Bool { mime.hasPrefix("image/") }

    /// The same file attached twice; pasted images are always distinct.
    func isSameFile(as other: Attachment) -> Bool {
        if case .file(let url) = source, case .file(let otherURL) = other.source { return url == otherURL }
        return false
    }

    var promptFile: PromptFile {
        switch source {
        case .file(let url):
            PromptFile(uri: url.absoluteString, name: name)
        case .inline(let data):
            PromptFile(uri: "data:\(mime);base64,\(data.base64EncodedString())", name: name, source: .init(type: "inline"))
        }
    }

    static func file(_ url: URL) -> Attachment? {
        // Folders are not attachable: the server only reads files.
        guard url.isFileURL, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        let thumbnail = type?.conforms(to: .image) == true
            ? CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { png(from: $0, maximumSize: thumbnailSize) }
            : nil
        return Attachment(name: url.lastPathComponent, mime: mime, source: .file(url), thumbnail: thumbnail)
    }

    /// Pasted or dropped image data in any format ImageIO reads, sent as PNG.
    static func image(_ data: Data, name: String = "image.png") -> Attachment? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let png = isSmallPNG(source) ? data : png(from: source, maximumSize: maximumImageSize)
        else { return nil }
        return Attachment(name: name, mime: "image/png", source: .inline(png), thumbnail: Self.png(from: source, maximumSize: thumbnailSize))
    }

    /// A file stored in a sent message; the server keeps its content inline.
    static func stored(name: String, mime: String, data: Data) -> Attachment {
        let thumbnail = mime.hasPrefix("image/")
            ? CGImageSourceCreateWithData(data as CFData, nil).flatMap { png(from: $0, maximumSize: thumbnailSize) }
            : nil
        return Attachment(name: name, mime: mime, source: .inline(data), thumbnail: thumbnail)
    }

    private static func isSmallPNG(_ source: CGImageSource) -> Bool {
        guard CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return max(width, height) <= maximumImageSize
    }

    private static func png(from source: CGImageSource, maximumSize: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
