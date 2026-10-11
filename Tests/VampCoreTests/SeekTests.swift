import Testing
@testable import VampCore

private let song = Song(title: "S", bpm: 120, layers: [
    Layer(id: "kick", name: "Kick", role: .drums, code: "s(\"bd*4\")"),
], sections: [
    Section(id: "intro", name: "Intro", bars: 8, layerIDs: ["kick"]),
    Section(id: "verse", name: "Verse", bars: 16, layerIDs: ["kick"]),
    Section(id: "chorus", name: "Chorus", bars: 8, layerIDs: ["kick"]),
])

@Suite struct SeekTests {
    @Test func eachSectionKnowsItsStartBar() {
        #expect(song.startBar(ofSection: "intro") == 0)
        #expect(song.startBar(ofSection: "verse") == 8)
        #expect(song.startBar(ofSection: "chorus") == 24)
        #expect(song.startBar(ofSection: "nope") == nil)
    }

    @Test func aBarBelongsToTheSectionThatContainsIt() {
        #expect(song.section(atBar: 0)?.id == "intro")
        #expect(song.section(atBar: 7.9)?.id == "intro")
        #expect(song.section(atBar: 8)?.id == "verse")
        #expect(song.section(atBar: 31.5)?.id == "chorus")
        #expect(song.section(atBar: 32) == nil)
    }

    @Test func nextGoesToTheFollowingSectionStart() {
        #expect(song.nextSectionStart(after: 0) == 8)
        #expect(song.nextSectionStart(after: 10) == 24)
        #expect(song.nextSectionStart(after: 25) == nil)
    }

    @Test func previousGoesToThisSectionStartFirstThenTheOneBefore() {
        #expect(song.previousSectionStart(before: 12) == 8)   // inside the verse: back to its start
        #expect(song.previousSectionStart(before: 8.5) == 0)  // just past the verse start: to the intro
        #expect(song.previousSectionStart(before: 0) == 0)
    }

    @Test func playingFromABarShiftsTheWholeProgramEarlier() {
        let code = song.composedCode(tailBars: 2, startBar: 8) ?? ""
        #expect(code.hasSuffix(".early(8)"))
        #expect(song.composedCode(tailBars: 2, startBar: 0)?.contains(".early(") == false)
    }

    /// Without the semicolon, JavaScript reads "setcps(...)\n(" as one call and playback fails.
    @Test func theTempoStatementEndsWithASemicolon() {
        for start in [0, 8] {
            let firstLine = song.composedCode(tailBars: 2, startBar: start)?.components(separatedBy: "\n").first
            #expect(firstLine == "setcps(120/60/4);")
        }
    }

    @Test func aLayerFirstPlaysAtTheStartOfItsFirstSection() {
        let arranged = Song(title: "S", bpm: 120, layers: song.layers + [Layer(id: "pad", name: "Pad", role: .pad, code: "x")],
                            sections: song.sections.map { s in var s = s; if s.id == "chorus" { s.layerIDs.append("pad") }; return s })
        #expect(arranged.firstBar(whereLayerPlays: "kick") == 0)
        #expect(arranged.firstBar(whereLayerPlays: "pad") == 24)
        #expect(arranged.firstBar(whereLayerPlays: "ghost") == nil)
        let loop = Song(title: "L", bpm: 120, layers: song.layers)
        #expect(loop.firstBar(whereLayerPlays: "kick") == 0)
    }

    @Test func playbackFromABarEndsAtTheSameSongTime() {
        #expect(song.playbackEnd(tailBars: 2, loopingSection: nil, startBar: 8) == 26)  // 32 + 2 - 8
        #expect(song.playbackEnd(tailBars: 2, loopingSection: nil) == 34)
    }
}
