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
                let stdout = PipeReader(out.fileHandleForReading)
                let stderr = PipeReader(err.fileHandleForReading)
                process.terminationHandler = { finished in
                    let output = Output(stdout: stdout.wait(), stderr: stderr.wait(), status: finished.terminationStatus)
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

/// Drains a pipe on its own thread until the tool closes it, so a chatty tool never blocks
/// on a full buffer. Exactly one thread reads the handle: FileHandle is not thread-safe.
private final class PipeReader: @unchecked Sendable {
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            data = handle.readDataToEndOfFile()
            done.signal()
        }
    }

    /// Blocks until the pipe reaches its end. The semaphore also publishes `data` to the caller.
    func wait() -> Data {
        done.wait()
        return data
    }
}
