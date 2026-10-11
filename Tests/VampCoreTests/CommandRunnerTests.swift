import Foundation
import Testing
@testable import VampCore

@Suite struct CommandRunnerTests {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    @Test func capturesLargeOutputOnBothPipesCompletely() async throws {
        // More than a pipe buffer (64 KB) on each stream, so a reader that stops early loses data.
        let script = "head -c 300000 /dev/zero | tr '\\0' o; head -c 200000 /dev/zero | tr '\\0' e >&2"
        let output = try await CommandRunner.run(shell, ["-c", script], timeout: 30)
        #expect(output.stdout.count == 300_000)
        #expect(output.stderr.count == 200_000)
        #expect(output.status == 0)
    }

    @Test func reportsTheExitStatus() async throws {
        let output = try await CommandRunner.run(shell, ["-c", "echo nope >&2; exit 3"], timeout: 30)
        #expect(output.status == 3)
        #expect(String(decoding: output.stderr, as: UTF8.self) == "nope\n")
    }

    @Test func stopsAProcessThatRunsPastItsTimeout() async throws {
        let started = Date()
        await #expect(throws: CommandRunner.Timeout.self) {
            _ = try await CommandRunner.run(shell, ["-c", "sleep 30"], timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func cancellingTheTaskStopsTheProcess() async throws {
        let started = Date()
        let task = Task { try await CommandRunner.run(shell, ["-c", "sleep 30"], timeout: 60) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
