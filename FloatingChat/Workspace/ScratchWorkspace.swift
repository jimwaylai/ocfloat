import Foundation

/// The neutral directory every Conversation is anchored to. It holds no content of its own.
enum ScratchWorkspace {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "tw.com.shitu.ocfloat/scratch", directoryHint: .isDirectory)
    }

    /// No trailing slash: the server matches session directories as plain strings.
    static var path: String { directory.standardizedFileURL.path }

    static func ensure(at directory: URL = directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
