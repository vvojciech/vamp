import Foundation
import Testing
@testable import VampCore

/// Builds events for one bar pattern, repeated `bars` times from `start`.
private func repeated(_ bar: [NoteEvent], bars: Int, start: Int = 0) -> [NoteEvent] {
    (start..<(start + bars)).flatMap { b in bar.map { e in NoteEvent(begin: e.begin + Double(b), end: e.end + Double(b), midi: e.midi, sound: e.sound, gain: e.gain) } }
}

private func notes(_ midis: [Double], length: Double = 0.25) -> [NoteEvent] {
    midis.enumerated().map { NoteEvent(begin: Double($0.offset) * length, end: Double($0.offset + 1) * length, midi: $0.element) }
}

private func layer(_ id: String, _ role: LayerRole, code: String = "x", gain: Double = 0.8) -> Layer {
    Layer(id: id, name: id, role: role, code: code, gain: gain)
}

@Suite struct MusicTheoryTests {
    @Test func detectsMajorAndMinorKeys() {
        let cMajor = notes([60, 62, 64, 65, 67, 69, 71, 72, 60, 64, 67, 60])
        #expect(MusicTheory.key(of: cMajor).name == "C major")
        let aMinor = notes([57, 60, 64, 57, 59, 60, 62, 64, 57, 64, 57, 60, 52, 57])
        #expect(MusicTheory.key(of: aMinor).name == "A minor")
    }

    @Test func inKeyRatioCountsOutsideNotes() {
        let key = MusicTheory.Key(tonic: 0, minor: false)
        #expect(MusicTheory.inKeyRatio(notes([60, 62, 64, 66]), key: key) == 0.75)
    }
}

@Suite struct CriticTests {
    @Test func aLoopScoresLowOnForm() {
        let song = Song(title: "L", bpm: 120, layers: [layer("d", .drums)])
        let card = SongCritic.measure(song: song, events: ["d": repeated(notes([36]), bars: 4)], bars: 4)
        #expect(card.score(.form) <= 3)
        #expect(card.notes(.form).first?.contains("sections") == true)
    }

    @Test func aContrastingSixtyFourBarFormScoresHigh() {
        let ids = ["d", "b", "c", "l"]
        let sections = [
            Section(id: "intro", name: "Intro", bars: 8, layerIDs: ["c"]),
            Section(id: "verse", name: "Verse", bars: 16, layerIDs: ["d", "b", "c"]),
            Section(id: "chorus", name: "Chorus", bars: 16, layerIDs: ids),
            Section(id: "break", name: "Breakdown", bars: 8, layerIDs: ["c", "l"]),
            Section(id: "chorus2", name: "Chorus 2", bars: 8, layerIDs: ids),
            Section(id: "outro", name: "Outro", bars: 8, layerIDs: ["c"]),
        ]
        let song = Song(title: "F", bpm: 120, layers: ids.map { layer($0, .lead) }, sections: sections)
        #expect(SongCritic.form(song).score >= 9)
    }

    @Test func identicalNeighbourSectionsArePenalised() {
        let sections = [Section(id: "a", name: "A", bars: 16, layerIDs: ["x"]), Section(id: "b", name: "B", bars: 16, layerIDs: ["x"]),
                        Section(id: "c", name: "C", bars: 16, layerIDs: ["x", "y"]), Section(id: "d", name: "D", bars: 16, layerIDs: ["y"])]
        let song = Song(title: "F", bpm: 120, layers: [layer("x", .lead), layer("y", .pad)], sections: sections)
        #expect(SongCritic.form(song).score <= 8)
    }

    @Test func energyNeedsARiseAndAFall() {
        #expect(SongCritic.energyScore([2, 5, 8, 4, 9, 3]).score >= 9)
        #expect(SongCritic.energyScore([5, 5, 5, 5]).score <= 5)
    }

    @Test func bassOnChordTonesAgrees() {
        let chord = [NoteEvent(begin: 0, end: 1, midi: 60), NoteEvent(begin: 0, end: 1, midi: 64), NoteEvent(begin: 0, end: 1, midi: 67)]
        #expect(SongCritic.bassAgreement(bass: notes([36, 43]), harmony: chord) == 1)
        #expect(SongCritic.bassAgreement(bass: notes([42, 37]), harmony: chord) == 0)
    }

    @Test func plainFourOnTheFloorIsWeakGroove() {
        let kick = repeated([0, 0.25, 0.5, 0.75].map { NoteEvent(begin: $0, end: $0 + 0.25, sound: "bd") }, bars: 8)
        #expect(SongCritic.groove(drums: kick, bars: 8, sectionStarts: [0]).score <= 5)
    }

    @Test func syncopatedVariedDrumsAreStrongGroove() {
        let bar: [NoteEvent] = [
            .init(begin: 0, end: 0.25, sound: "bd"), .init(begin: 0.375, end: 0.5, sound: "bd", gain: 0.7),
            .init(begin: 0.25, end: 0.5, sound: "sd"), .init(begin: 0.75, end: 1, sound: "sd"),
            .init(begin: 0.125, end: 0.25, sound: "hh", gain: 0.6), .init(begin: 0.625, end: 0.75, sound: "hh"),
            .init(begin: 0.875, end: 1, sound: "oh"),
        ]
        var drums = repeated(bar, bars: 8)
        drums.append(.init(begin: 7.9375, end: 8, sound: "lt"))
        #expect(SongCritic.groove(drums: drums, bars: 8, sectionStarts: [0]).score >= 9)
    }

    @Test func melodyWantsRangeAndAMotif() {
        let motif: [Double] = [67, 70, 72, 70, 67, 65, 67, 74]
        let line = (0..<4).flatMap { i in notes(motif.map { $0 + (i == 3 ? 2 : 0) }, length: 0.125).map {
            NoteEvent(begin: $0.begin + Double(i), end: $0.end + Double(i), midi: $0.midi) } }
        #expect(SongCritic.melody(line).score >= 9)
        #expect(SongCritic.melody(repeated(notes([60, 60, 60, 60]), bars: 4)).score <= 6)
        #expect(SongCritic.melody([]).score <= 3)
    }

    @Test func soundDesignRewardsEffectsMovementAndPalette() {
        let rich = [
            layer("d", .drums, code: "s(\"bd sd, hh*8\").bank(\"RolandTR909\").room(0.2).pan(sine)"),
            layer("b", .bass, code: "note(\"c2\").s(\"sawtooth\").lpf(sine.range(300,900).slow(8)).decay(0.2)"),
            layer("p", .chords, code: "chord(\"Cm9\").voicing().s(\"piano\").room(0.4).release(1)"),
            layer("l", .lead, code: "n(\"0 2\").scale(\"C:minor\").s(\"vibraphone\").delay(0.3).room(0.3)"),
            layer("x", .pad, code: "chord(\"Cm\").voicing().s(\"supersaw\").attack(1).lpf(800).jux(rev)"),
        ]
        #expect(SongCritic.soundDesign(Song(title: "S", bpm: 100, layers: rich)).score >= 9)
        let plain = [layer("a", .lead, code: "note(\"c3\").s(\"square\")"), layer("b", .bass, code: "note(\"c2\").s(\"square\")")]
        #expect(SongCritic.soundDesign(Song(title: "S", bpm: 100, layers: plain)).score <= 4)
    }

    @Test func mixFlagsLoudLayersAndHighBass() {
        let song = Song(title: "M", bpm: 100, layers: [layer("b", .bass, gain: 1.5), layer("d", .drums, gain: 0.9)])
        let card = SongCritic.mix(song, events: ["b": notes([64, 67])], sections: [(0..<4, ["b", "d"])])
        #expect(card.score <= 8)
        #expect(card.notes.contains { $0.contains("too loud") })
        #expect(card.notes.contains { $0.contains("sits high") })
    }

    @Test func quietHatsAreFineButAQuietKickIsNot() {
        let song = Song(title: "M", bpm: 100, layers: [layer("hats", .drums, gain: 0.4), layer("kick", .drums, gain: 0.4)])
        let events = ["hats": [NoteEvent(begin: 0, end: 0.1, sound: "hh")], "kick": [NoteEvent(begin: 0, end: 0.1, sound: "bd")]]
        let notes = SongCritic.mix(song, events: events, sections: [(0..<4, ["hats", "kick"])]).notes
        #expect(notes.count == 1)
        #expect(notes.first?.hasPrefix("kick is quiet") == true)
    }

    @Test func scorecardOverallIsTheLowestAspect() {
        let card = Scorecard(aspects: [.init(name: .form, score: 9.5, notes: []), .init(name: .mix, score: 7, notes: [])])
        #expect(card.overall == 7)
    }
}
