import Foundation

/// Runs a command-line tool and collects everything it prints.
public enum CommandRunner {
    public struct Output: Sendable {
        public var stdout: Data
        public var stderr: Data
        public var status: Int32
    }

    /// The tool ran longer than its time limit and was stopped.
    public struct Timeout: Error, LocalizedError {
        public var seconds: TimeInterval
        public var errorDescription: String? { "The command took longer than \(Int(seconds)) seconds and was stopped." }
    }

    public static func run(_ executable: URL, _ arguments: [String], directory: URL? = nil,
                           environment: [String: String]? = nil, timeout: TimeInterval) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let timedOut = Flag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let stdout = PipeReader(out.fileHandleForReading)
                let stderr = PipeReader(err.fileHandleForReading)
                process.terminationHandler = { finished in
                    let output = Output(stdout: stdout.wait(), stderr: stderr.wait(), status: finished.terminationStatus)
                    if timedOut.isSet {
                        continuation.resume(throwing: Timeout(seconds: timeout))
                    } else if finished.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: output)
                    }
                }
                do { try process.run() } catch { continuation.resume(throwing: error); return }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    timedOut.set()
                    process.terminate()
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

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
