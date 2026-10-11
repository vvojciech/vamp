import Testing
@testable import VampCore

@Suite struct AgentGuideTests {
    @Test(arguments: ["Classical", "Techno", "Rock", "Dubstep", "Pop", "House", "Hip-hop", "Jazz", "Ambient", "Drum and bass"])
    func theGuideCoversEachTargetGenre(_ genre: String) {
        #expect(AgentPrompt.system.contains("\(genre):"))
    }

    @Test func theGuideTellsTheComposerToUseTheGenresRealInstruments() {
        #expect(AgentPrompt.system.contains("Use the genre's real instruments"))
    }
}
