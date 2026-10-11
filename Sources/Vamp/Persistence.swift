import Foundation
import VampCore

/// Keeps the current song and the agent log between launches.
enum Persistence {
    struct Snapshot: Codable {
        var song: Song
        var chat: [ChatEntry]
        /// The latest scores with their notes. Optional, so older session files still load.
        var scorecard: Scorecard?
        var scorecardJudged: Bool?
    }

    private static var url: URL {
        // VAMP_SESSION points a test instance at its own file, so it never touches real work.
        if let path = ProcessInfo.processInfo.environment["VAMP_SESSION"] { return URL(fileURLWithPath: path) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Vamp", isDirectory: true).appendingPathComponent("session.json")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            print("[vamp] save failed:", error.localizedDescription)
        }
    }
}
