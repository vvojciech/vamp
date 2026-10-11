import Testing
@testable import Vamp

@Suite struct BigRequestTests {
    /// One request per keyword, so dropping any keyword fails a case.
    @Test(arguments: ["Compose something moody", "write a song about rain", "turn this into a full song",
                      "extend it into the whole song", "start a new song in D minor", "arrange this loop"])
    func wholeSongRequestsGetTheComposer(_ request: String) {
        #expect(AppModel.isBigRequest(request))
    }

    @Test func smallEditsKeepTheChosenModel() {
        #expect(!AppModel.isBigRequest("make the hats quieter"))
        #expect(!AppModel.isBigRequest("add a dreamy pad under everything"))
    }

    @Test func theComposerIsTheStrongestModelPerBackend() {
        #expect(BackendKind.claudeCLI.composerModel == "opus")
        #expect(BackendKind.anthropicAPI.composerModel == "claude-opus-5")
        #expect(BackendKind.codexCLI.composerModel.isEmpty)  // Codex default
    }
}
