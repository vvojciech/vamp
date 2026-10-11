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

@Suite struct AgentGuideEditingTests {
    @Test func theGuideLimitsAnEditToWhatTheRequestNames() {
        #expect(AgentPrompt.system.contains("Change only the layers and sections the request names"))
    }

    @Test func theGuideChecksTheDirectionOfRelativeChanges() {
        #expect(AgentPrompt.system.contains("check the direction"))
        #expect(AgentPrompt.system.contains("a faster wobble needs higher fast() values"))
    }

    @Test func theGuideSaysWhatToDoWhenTheThingAlreadyExists() {
        #expect(AgentPrompt.system.contains("already exists"))
    }
}
