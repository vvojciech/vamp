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
}
