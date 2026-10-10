import Foundation
import VampCore

/// Runs a command-line tool the way a terminal would, from inside a Finder-launched app.
enum CLI {
    struct Output {
        var stdout: Data
        var stderr: Data
        var status: Int32

        var stderrSummary: String? {
            let text = String(decoding: stderr, as: UTF8.self)
                .split(separator: "\n").map(String.init)
                .filter { !$0.isEmpty && !$0.hasPrefix("Reading additional input") }
                .suffix(3).joined(separator: " ")
            return text.isEmpty ? nil : String(text.prefix(400))
        }
    }

    /// Apps started from Finder get a bare PATH, so add the usual install folders.
    static let searchPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local",
                "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin",
                "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
    }()

    static func locate(_ tool: String) -> URL? {
        for dir in searchPath.split(separator: ":") {
            let url = URL(fileURLWithPath: String(dir)).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// An empty working folder, so no project files leak into the agent's context.
    static func scratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vamp-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 180) async throws -> Output {
        guard let executable = locate(tool) else {
            throw BackendError.message("Vamp cannot find the \(tool) CLI. Install it and sign in, then try again.")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = try scratchDirectory()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let stdout = Collector(out.fileHandleForReading)
                let stderr = Collector(err.fileHandleForReading)
                process.terminationHandler = { finished in
                    let output = Output(stdout: stdout.finish(), stderr: stderr.finish(), status: finished.terminationStatus)
                    if finished.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: output)
                    }
                }
                do { try process.run() } catch { continuation.resume(throwing: error); return }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Drains a pipe as it fills, so a chatty tool never blocks on a full buffer.
private final class Collector: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self, !chunk.isEmpty else { return }
            self.lock.withLock { self.data.append(chunk) }
        }
    }

    func finish() -> Data {
        handle.readabilityHandler = nil
        let rest = handle.readDataToEndOfFile()
        return lock.withLock { data + rest }
    }
}
