import Foundation

/// Apps launched from Finder or at login do not inherit the shell's `PATH`, so well-known
/// install locations are searched explicitly.
enum ExecutableLocator {
    static func candidates(configured: String?, pathEnvironment: String?, home: String) -> [String] {
        var result: [String] = []
        if let configured, !configured.isEmpty {
            result.append((configured as NSString).expandingTildeInPath)
        }
        for directory in (pathEnvironment ?? "").split(separator: ":") where !directory.isEmpty {
            result.append("\(directory)/opencode")
        }
        result += [
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            "\(home)/.opencode/bin/opencode",
        ]
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    static func locate(
        configured: String?,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        home: String = NSHomeDirectory(),
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> String? {
        candidates(configured: configured, pathEnvironment: pathEnvironment, home: home).first(where: isExecutable)
    }
}
