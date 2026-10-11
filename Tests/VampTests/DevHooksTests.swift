import Testing
@testable import Vamp

@Suite struct DevHooksTests {
    @Test func aPromptFileGivesOnePromptPerLineInOrder() {
        let file = """
        # synthwave scenario
        Compose a full song: a moody synthwave night-drive track

          Make the chorus hit harder  
        # a comment between steps
        Slow it down to 96 BPM
        """
        #expect(DevHooks.prompts(fromFile: file) == [
            "Compose a full song: a moody synthwave night-drive track",
            "Make the chorus hit harder",
            "Slow it down to 96 BPM",
        ])
    }

    @Test func anEmptyFileGivesNoPrompts() {
        #expect(DevHooks.prompts(fromFile: "\n# only a comment\n").isEmpty)
    }
}
