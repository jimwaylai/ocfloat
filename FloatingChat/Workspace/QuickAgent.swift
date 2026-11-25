import Foundation

/// The opencode agent every Conversation runs with. It lives in the user's global opencode
/// config so the user can tune it; the app only writes it when it is missing.
enum QuickAgent {
    static let id = "quick-chat"

    static var file: URL {
        let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config")
        return configHome.appending(path: "opencode/agents/\(id).md")
    }

    /// Everything is denied first and the web tools re-allowed after, so the user's global
    /// permission rules can neither widen access nor cause permission prompts.
    static let defaultContents = """
        ---
        description: Quick answers for ocfloat
        mode: primary
        hidden: true
        steps: 8
        permissions:
          - action: "*"
            resource: "*"
            effect: deny
          - action: websearch
            resource: "*"
            effect: allow
          - action: webfetch
            resource: "*"
            effect: allow
        ---

        You answer quick questions asked from a floating chat window on macOS.

        - Lead with the answer. Add a short explanation only when it helps.
        - Use Markdown when it improves readability: lists, tables, fenced code blocks with a language.
        - Reply in the language the user writes in.
        - You cannot see the user's files or projects. Search or fetch the web when the question needs current or specific facts, and cite the sources you used.

        """

    /// Returns `true` when the file was written; an existing file is never touched.
    @discardableResult
    static func installIfMissing(at file: URL = file) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return false }
        try write(to: file)
        return true
    }

    static func restoreDefaults(at file: URL = file) throws {
        try write(to: file)
    }

    private static func write(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(defaultContents.utf8).write(to: file, options: .atomic)
    }
}
