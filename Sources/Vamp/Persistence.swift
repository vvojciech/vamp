import Foundation
import VampCore

/// Keeps the current song and the agent log between launches.
enum Persistence {
    struct Snapshot: Codable {
        var song: Song
        var chat: [ChatEntry]
    }

    private static var url: URL {
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
