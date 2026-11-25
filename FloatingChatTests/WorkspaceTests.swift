import Testing
import Foundation
@testable import FloatingChat

struct WorkspaceTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ocf-workspace-\(UUID().uuidString)")

    @Test func scratchWorkspaceLivesInAppSupport() {
        #expect(ScratchWorkspace.path.hasSuffix("/Library/Application Support/tw.com.shitu.ocfloat/scratch"))
    }

    @Test func ensureCreatesNestedDirectory() throws {
        let directory = root.appending(path: "a/scratch")
        defer { try? FileManager.default.removeItem(at: root) }
        try ScratchWorkspace.ensure(at: directory)
        try ScratchWorkspace.ensure(at: directory)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test func installsAgentOnlyWhenMissing() throws {
        let file = root.appending(path: "agents/quick-chat.md")
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try QuickAgent.installIfMissing(at: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == QuickAgent.defaultContents)

        try Data("custom".utf8).write(to: file)
        #expect(try !QuickAgent.installIfMissing(at: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == "custom")

        try QuickAgent.restoreDefaults(at: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == QuickAgent.defaultContents)
    }

    @Test func defaultAgentDeniesEverythingButWebTools() {
        let contents = QuickAgent.defaultContents
        #expect(contents.hasPrefix("---\n"))
        #expect(contents.contains("hidden: true"))
        let deny = contents.range(of: "action: \"*\"")!
        #expect(contents.range(of: "action: websearch")!.lowerBound > deny.lowerBound)
        #expect(contents.range(of: "action: webfetch")!.lowerBound > deny.lowerBound)
    }
}
