import Foundation
import Testing
@testable import VampCore

/// The Node engine test plays the starter song. This keeps its copy in step with Swift.
@Suite struct StarterFixtureTests {
    @Test func engineFixtureMatchesStarterSong() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../engine/starter.json").standardized
        let stored = try? JSONDecoder().decode(Song.self, from: Data(contentsOf: url))
        if stored != Song.starter {
            try AgentPrompt.encoder.encode(Song.starter).write(to: url)
            Issue.record("starter.json was out of date and has been rewritten. Run the tests again.")
        }
    }

    /// A full program as the app plays it: an arranged song with a tail, started at bar 8.
    /// The Node test runs it through the Strudel transpiler, as the REPL does.
    @Test func engineFixtureMatchesAComposedProgram() throws {
        var song = Song.starter
        song.sections = [Section(id: "a", name: "A", bars: 8, layerIDs: ["drums", "bass"]),
                         Section(id: "b", name: "B", bars: 8, layerIDs: song.layers.map(\.id))]
        let program = try #require(song.composedCode(tailBars: 2, startBar: 8))
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../engine/composed-program.js").standardized
        if (try? String(contentsOf: url, encoding: .utf8)) != program {
            try program.write(to: url, atomically: true, encoding: .utf8)
            Issue.record("composed-program.js was out of date and has been rewritten. Run the tests again.")
        }
    }
}
