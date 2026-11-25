import Foundation

enum ServiceLauncher {
    private static let timeout: TimeInterval = 20

    /// Runs `opencode service start` and reports whether it exited successfully.
    static func start(executable: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["service", "start"]
            var environment = ProcessInfo.processInfo.environment
            let directory = (executable as NSString).deletingLastPathComponent
            environment["PATH"] = [directory, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""]
                .joined(separator: ":")
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
                return
            }
            nonisolated(unsafe) let running = process
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if running.isRunning { running.terminate() }
            }
        }
    }
}
