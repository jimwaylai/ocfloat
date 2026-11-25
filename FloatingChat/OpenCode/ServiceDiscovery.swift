import Foundation

/// The runtime record the opencode background service writes while it is running.
struct ServiceInfo: Decodable, Equatable, Sendable {
    let url: URL
    let password: String
    let pid: Int32?
}

enum ServiceDiscovery {
    static var stateFile: URL {
        let stateHome = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/state")
        return stateHome.appending(path: "opencode/service.json")
    }

    /// `nil` when the file is missing or unreadable, or the recorded process is gone (a stale file).
    static func read(at file: URL = stateFile, isAlive: (Int32) -> Bool = processIsAlive) -> ServiceInfo? {
        guard let data = try? Data(contentsOf: file),
              let info = try? JSONDecoder().decode(ServiceInfo.self, from: data)
        else { return nil }
        if let pid = info.pid, !isAlive(pid) { return nil }
        return info
    }

    static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
