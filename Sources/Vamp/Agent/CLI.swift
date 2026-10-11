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
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        do {
            let output = try await CommandRunner.run(executable, arguments, directory: try scratchDirectory(),
                                                     environment: env, timeout: timeout)
            return Output(stdout: output.stdout, stderr: output.stderr, status: output.status)
        } catch let timeout as CommandRunner.Timeout {
            throw BackendError.message("\(tool) did not answer in time. \(timeout.localizedDescription)")
        }
    }
}
