import Testing
@testable import VampCore

private func layer(_ id: String, _ code: String, gain: Double = 0.8, muted: Bool = false, solo: Bool = false) -> Layer {
    Layer(id: id, name: id.capitalized, role: .drums, code: code, gain: gain, muted: muted, solo: solo)
}

@Suite struct SongTests {
    @Test func composeStacksAudibleLayersWithTempoAndGain() {
        let song = Song(title: "T", bpm: 120, layers: [layer("kick", "s(\"bd*4\")"), layer("hats", "s(\"hh*8\")", gain: 0.5)])
        let code = song.composedCode()
        #expect(code == """
        setcps(120/60/4);
        stack(
          (
        s("bd*4")
          ).postgain(0.80),
          (
        s("hh*8")
          ).postgain(0.50)
        )
        """)
    }

    @Test func mutedLayersAreLeftOut() {
        let song = Song(title: "T", bpm: 90, layers: [layer("a", "s(\"bd\")", muted: true), layer("b", "s(\"sd\")")])
        #expect(song.audibleLayers.map(\.id) == ["b"])
    }

    @Test func soloWinsOverEverythingElse() {
        let song = Song(title: "T", bpm: 90, layers: [layer("a", "x"), layer("b", "y", solo: true), layer("c", "z", muted: true, solo: true)])
        #expect(song.audibleLayers.map(\.id) == ["b", "c"])
    }

    @Test func noAudibleLayersMeansNoCode() {
        let song = Song(title: "T", bpm: 90, layers: [layer("a", "x", muted: true)])
        #expect(song.composedCode() == nil)
    }

    @Test func overridesReplaceLayerCode() {
        let song = Song(title: "T", bpm: 100, layers: [layer("a", "broken(")])
        let code = song.composedCode(codeOverrides: ["a": "s(\"bd\")"])
        #expect(code?.contains("s(\"bd\")") == true)
        #expect(code?.contains("broken(") == false)
    }

    @Test func trailingSemicolonsAndBlankLinesAreTrimmed() {
        #expect(Layer.cleaned("  s(\"bd\");\n\n") == "s(\"bd\")")
    }

    @Test func uniqueIDsAreSlugsWithSuffixes() {
        let song = Song(title: "T", bpm: 100, layers: [layer("bass", "x")])
        #expect(song.uniqueID(for: "Deep Bass!") == "deep-bass")
        #expect(song.uniqueID(for: "Bass") == "bass-2")
        #expect(song.uniqueID(for: "!!!") == "layer")
    }

    @Test func starterSongHasLayersAndCode() {
        let song = Song.starter
        #expect(song.layers.count >= 3)
        #expect(song.composedCode() != nil)
    }
}
