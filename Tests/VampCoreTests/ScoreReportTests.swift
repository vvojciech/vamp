import Foundation
import Testing
@testable import VampCore

/// A tool, not a check: prints the score card of a saved song. It runs only when both
/// SCORE_SESSION and SCORE_EVENTS are set (see scripts/song-events.mjs).
@Suite struct ScoreReport {
    private struct Session: Decodable { var song: Song }
    private struct Analysis: Decodable { var bars: Int; var events: [String: [NoteEvent]] }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCORE_EVENTS"] != nil))
    func printScorecard() throws {
        let env = ProcessInfo.processInfo.environment
        let session = try JSONDecoder().decode(Session.self, from: Data(contentsOf: URL(fileURLWithPath: env["SCORE_SESSION"]!)))
        let analysis = try JSONDecoder().decode(Analysis.self, from: Data(contentsOf: URL(fileURLWithPath: env["SCORE_EVENTS"]!)))
        let card = SongCritic.measure(song: session.song, events: analysis.events, bars: analysis.bars)
        print("SCORE \(String(format: "%.1f", card.overall))\n\(card.report)")
        // SCORE_JUDGE_DIR writes the judge's prompt files, for checking how consistent the judge is.
        if let dir = env["SCORE_JUDGE_DIR"] {
            let base = URL(fileURLWithPath: dir)
            try Critique.system.write(to: base.appendingPathComponent("judge-system.txt"), atomically: true, encoding: .utf8)
            try Critique.prompt(song: session.song, measured: card).write(to: base.appendingPathComponent("judge-user.txt"), atomically: true, encoding: .utf8)
            try Critique.jsonSchema.write(to: base.appendingPathComponent("judge-schema.json"), atomically: true, encoding: .utf8)
        }
    }
}
