import Foundation
import Testing
@testable import VampCore

private func song(sections: [Section] = []) -> Song {
    Song(title: "S", bpm: 100, layers: [
        Layer(id: "drums", name: "Drums", role: .drums, code: "s(\"bd*4\")"),
        Layer(id: "pad", name: "Pad", role: .pad, code: "note(\"c3\")"),
    ], sections: sections)
}

@Suite struct SectionTests {
    @Test func withoutSectionsTheProgramIsTheLayerCode() {
        let s = song()
        #expect(s.program(for: s.layers[0]) == "s(\"bd*4\")")
        #expect(s.totalBars == nil)
    }

    @Test func sectionsArrangeEachLayerWithSilenceWhereItRests() {
        let s = song(sections: [
            Section(id: "intro", name: "Intro", bars: 4, layerIDs: ["pad"]),
            Section(id: "main", name: "Main", bars: 8, layerIDs: ["drums", "pad"]),
        ])
        #expect(s.totalBars == 12)
        #expect(s.program(for: s.layers[0]) == "arrange(\n  [4, silence],\n  [8, (\ns(\"bd*4\")\n  )]\n)")
    }

    @Test func variationsReplaceLayerCodeInOneSection() {
        var main = Section(id: "main", name: "Main", bars: 4, layerIDs: ["pad"])
        main.variations["pad"] = "note(\"g3\")"
        let s = song(sections: [Section(id: "a", name: "A", bars: 2, layerIDs: ["pad"]), main])
        let program = s.program(for: s.layers[1])
        #expect(program?.contains("[2, (\nnote(\"c3\")") == true)
        #expect(program?.contains("[4, (\nnote(\"g3\")") == true)
    }

    @Test func layerInNoSectionHasNoProgramAndIsLeftOut() {
        let s = song(sections: [Section(id: "intro", name: "Intro", bars: 4, layerIDs: ["pad"])])
        #expect(s.program(for: s.layers[0]) == nil)
        #expect(s.composedCode()?.contains("bd*4") == false)
    }

    @Test func aSongWithSectionsEndsAfterItsBarsAndTheTail() {
        let s = song(sections: [Section(id: "a", name: "A", bars: 4, layerIDs: ["pad"]),
                                Section(id: "b", name: "B", bars: 8, layerIDs: ["pad"])])
        #expect(s.playbackEnd(tailBars: 2, loopingSection: nil) == 14)
    }

    @Test func aLoopOrALoopedSectionNeverEnds() {
        let arranged = song(sections: [Section(id: "a", name: "A", bars: 4, layerIDs: ["pad"])])
        #expect(arranged.playbackEnd(tailBars: 2, loopingSection: "a") == nil)
        #expect(song().playbackEnd(tailBars: 2, loopingSection: nil) == nil)
    }

    @Test func aTailOfSilenceWrapsTheWholeSong() {
        let s = song(sections: [Section(id: "a", name: "A", bars: 4, layerIDs: ["drums"])])
        let code = s.composedCode(tailBars: 2) ?? ""
        #expect(code.hasPrefix("setcps(100/60/4)\narrange(\n[4, stack("))
        #expect(code.hasSuffix(")],\n[2, silence]\n)"))
        #expect(s.composedCode(tailBars: 2, onlySection: "a")?.contains("silence]") == false)
    }

    @Test func loopingOneSectionPlaysOnlyItsLayers() {
        let s = song(sections: [
            Section(id: "intro", name: "Intro", bars: 4, layerIDs: ["pad"]),
            Section(id: "main", name: "Main", bars: 8, layerIDs: ["drums", "pad"]),
        ])
        let code = s.composedCode(onlySection: "intro")
        #expect(code?.contains("note(\"c3\")") == true)
        #expect(code?.contains("bd*4") == false)
        #expect(code?.contains("arrange") == false)
    }

    @Test func firstSectionWrapsTheExistingLoopAsMain() throws {
        var s = song()
        let change = try EditPlan.Edit(op: .addSection, name: "Intro", bars: 4, layers: ["pad"], position: 0).apply(to: &s)
        #expect(s.sections.map(\.name) == ["Intro", "Main"])
        #expect(s.sections[1].layerIDs == ["drums", "pad"])
        #expect(change == .sectionAdded("intro"))
    }

    @Test func addSectionDefaultsToAllLayersAtTheEnd() throws {
        var s = song(sections: [Section(id: "main", name: "Main", bars: 8, layerIDs: ["drums"])])
        try EditPlan.Edit(op: .addSection, name: "Outro").apply(to: &s)
        #expect(s.sections.last?.layerIDs == ["drums", "pad"])
        #expect(s.sections.last?.bars == 8)
    }

    @Test func addLayerForOneSectionPlaysOnlyThere() throws {
        var s = song(sections: [Section(id: "a", name: "A", bars: 4, layerIDs: ["drums"]),
                                Section(id: "b", name: "B", bars: 4, layerIDs: ["drums"])])
        try EditPlan.Edit(op: .addLayer, sectionID: "b", name: "Lead", role: .lead, code: "note(\"e4\")").apply(to: &s)
        #expect(s.sections[0].layerIDs == ["drums"])
        #expect(s.sections[1].layerIDs == ["drums", "lead"])
    }

    @Test func addLayerWithoutSectionJoinsEverySection() throws {
        var s = song(sections: [Section(id: "a", name: "A", bars: 4, layerIDs: ["drums"])])
        try EditPlan.Edit(op: .addLayer, name: "Lead", role: .lead, code: "note(\"e4\")").apply(to: &s)
        #expect(s.sections[0].layerIDs == ["drums", "lead"])
    }

    @Test func updateLayerWithSectionSetsAVariation() throws {
        var s = song(sections: [Section(id: "a", name: "A", bars: 4, layerIDs: ["pad"])])
        let change = try EditPlan.Edit(op: .updateLayer, layerID: "pad", sectionID: "a", code: "note(\"a3\")").apply(to: &s)
        #expect(s.sections[0].variations["pad"] == "note(\"a3\")")
        #expect(s.layers[1].code == "note(\"c3\")")
        #expect(change == .changed("pad"))
    }

    @Test func updateSectionMovesAndResizes() throws {
        var s = song(sections: [Section(id: "a", name: "A", bars: 4, layerIDs: []),
                                Section(id: "b", name: "B", bars: 4, layerIDs: [])])
        try EditPlan.Edit(op: .updateSection, sectionID: "b", bars: 500, layers: ["pad", "ghost"], position: 0).apply(to: &s)
        #expect(s.sections.map(\.id) == ["b", "a"])
        #expect(s.sections[0].bars == Section.barRange.upperBound)
        #expect(s.sections[0].layerIDs == ["pad"])
    }

    @Test func removingALayerCleansSections() throws {
        var main = Section(id: "main", name: "Main", bars: 4, layerIDs: ["drums", "pad"])
        main.variations["pad"] = "x"
        var s = song(sections: [main])
        try EditPlan.Edit(op: .removeLayer, layerID: "pad").apply(to: &s)
        #expect(s.sections[0].layerIDs == ["drums"])
        #expect(s.sections[0].variations.isEmpty)
    }

    @Test func removeSectionAndUnknownSectionError() throws {
        var s = song(sections: [Section(id: "a", name: "A", bars: 4, layerIDs: [])])
        #expect(try EditPlan.Edit(op: .removeSection, sectionID: "a").apply(to: &s) == .sectionRemoved("a"))
        #expect(throws: EditError.self) { try EditPlan.Edit(op: .updateSection, sectionID: "a", bars: 2).apply(to: &s) }
    }

    @Test func oldSavedSongsWithoutSectionsStillDecode() throws {
        let json = #"{"title":"T","bpm":100,"layers":[]}"#
        #expect(try JSONDecoder().decode(Song.self, from: Data(json.utf8)).sections.isEmpty)
    }
}
