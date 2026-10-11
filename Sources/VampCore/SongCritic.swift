import Foundation

/// Measures a song from its analysed notes. The rules are simple and strict on purpose:
/// they catch what a listener notices first, and every note says what to change.
public enum SongCritic {
    /// - Parameters:
    ///   - events: note events per layer id, over the whole song (or `bars` bars for a loop).
    ///   - bars: the analysed length when the song has no sections.
    public static func measure(song: Song, events: [String: [NoteEvent]], bars: Int) -> Scorecard {
        let windows = sectionWindows(song, bars: bars)
        func role(_ id: String) -> LayerRole? { song.layers.first { $0.id == id }?.role }
        func eventsFor(_ roles: Set<LayerRole>) -> [NoteEvent] {
            events.filter { role($0.key).map(roles.contains) ?? false }.flatMap(\.value)
        }

        let energies = windows.map { window in
            song.layers.reduce(0.0) { total, layer in
                let inside = (events[layer.id] ?? []).filter { window.range.contains(Int($0.begin)) }
                guard !inside.isEmpty else { return total }
                let perBar = Double(inside.count) / Double(max(window.range.count, 1))
                let weight: Double = [.drums, .percussion].contains(layer.role) ? 1.2 : layer.role == .bass ? 1 : 0.8
                return total + 0.5 + min(perBar, 16) / 16 * weight
            }
        }

        // The melody is the lead when there is one; an arp is accompaniment unless it is all there is.
        let leads = song.layers.filter { $0.role == .lead }
        let melodic = (leads.isEmpty ? song.layers.filter { $0.role == .arp } : leads)
            .max { (events[$0.id]?.count ?? 0) < (events[$1.id]?.count ?? 0) }

        return Scorecard(aspects: [
            form(song).aspect(.form),
            (song.sections.isEmpty ? loopEnergy() : energyScore(energies)).aspect(.energy),
            harmony(pitched: eventsFor([.bass, .chords, .pad, .lead, .arp]), bass: eventsFor([.bass]),
                    chords: eventsFor([.chords, .pad])).aspect(.harmony),
            groove(drums: eventsFor([.drums, .percussion]), bars: song.totalBars ?? bars,
                   sectionStarts: windows.map(\.range.lowerBound)).aspect(.groove),
            melody(melodic.flatMap { events[$0.id] } ?? []).aspect(.melody),
            soundDesign(song).aspect(.sound),
            mix(song, events: events, sections: windows.map { ($0.range, $0.layerIDs) }).aspect(.mix),
        ])
    }

    static func sectionWindows(_ song: Song, bars: Int) -> [(range: Range<Int>, layerIDs: [String])] {
        guard !song.sections.isEmpty else { return [(0..<bars, song.layers.map(\.id))] }
        var start = 0
        return song.sections.map { section in
            defer { start += section.bars }
            return (start..<(start + section.bars), section.layerIDs)
        }
    }

    // MARK: Form

    public static func form(_ song: Song) -> Measured {
        guard let total = song.totalBars else {
            var m = Measured(score: 3)
            m.penalise(0, "The song is one loop. Add sections: intro, verse, chorus, a breakdown or bridge, and an outro.")
            return m
        }
        var m = Measured()
        if total < 24 { m.penalise(4, "The song is \(total) bars. Make it at least 64 bars (about 2 to 3 minutes).") }
        else if total < 40 { m.penalise(2, "The song is \(total) bars. Make it at least 64 bars.") }
        else if total < 56 { m.penalise(1, "The song is \(total) bars. 64 bars or more gives the arrangement room.") }
        if song.sections.count < 4 { m.penalise(3, "Only \(song.sections.count) sections. Use at least 5, with a clear start, a peak and an end.") }
        else if song.sections.count < 5 { m.penalise(1, "Add one more section, such as a breakdown before the last chorus.") }
        for (a, b) in zip(song.sections, song.sections.dropFirst()) where Set(a.layerIDs) == Set(b.layerIDs) && a.variations == b.variations {
            m.penalise(2, "\(a.name) and \(b.name) are next to each other and sound the same. Change the layers or give one its own variations.")
        }
        return m
    }

    // MARK: Energy

    static func loopEnergy() -> Measured {
        var m = Measured(score: 4)
        m.penalise(0, "A loop has no energy arc. Sections must build, release and build again.")
        return m
    }

    public static func energyScore(_ energies: [Double]) -> Measured {
        var m = Measured()
        guard energies.count >= 3, let peak = energies.max(), let first = energies.first, let last = energies.last else {
            m.penalise(5, "With fewer than 3 sections there is no arc. Build from a quiet start to a peak and back.")
            return m
        }
        let mean = energies.reduce(0, +) / Double(energies.count)
        let spread = (energies.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(energies.count)).squareRoot() / max(mean, 0.01)
        if peak < first * 1.3 { m.penalise(3, "The start is nearly as busy as the peak. Start with fewer layers.") }
        if peak < last * 1.15 { m.penalise(2, "The end is as busy as the peak. Thin the last section out for closure.") }
        if spread < 0.15 { m.penalise(3, "All sections have about the same energy. Vary the number of layers and their density.") }
        if energies.firstIndex(of: peak) == 0 { m.penalise(2, "The first section is the busiest. Save the peak for later.") }
        let peakIndex = energies.firstIndex(of: peak) ?? 0
        let dipAfterRise = energies.indices.dropFirst().contains { i in i < peakIndex && energies[i] < energies[i - 1] * 0.8 }
            || energies[(peakIndex + 1)...].dropLast().contains { $0 < peak * 0.7 }
        if energies.count >= 5 && !dipAfterRise { m.penalise(1, "Add a breakdown: a quieter section between two big ones.") }
        return m
    }

    // MARK: Harmony

    static func harmony(pitched: [NoteEvent], bass: [NoteEvent], chords: [NoteEvent]) -> Measured {
        var m = Measured()
        guard !pitched.isEmpty else {
            m.penalise(8, "No pitched layers. Add bass, chords and a melody.")
            return m
        }
        let key = MusicTheory.key(of: pitched)
        let ratio = MusicTheory.inKeyRatio(pitched, key: key)
        let outside = MusicTheory.histogram(pitched).enumerated()
            .filter { !key.pitchClasses.contains($0.offset) && $0.element > 0 }
            .sorted { $0.element > $1.element }.prefix(3).map { MusicTheory.pitchNames[$0.offset] }
        let outsideText = outside.joined(separator: ", ")
        if ratio < 0.8 { m.penalise(6, "Only \(Int(ratio * 100))% of notes are in \(key.name). Outside notes: \(outsideText).") }
        else if ratio < 0.88 { m.penalise(3, "\(Int(ratio * 100))% of notes are in \(key.name). Check \(outsideText).") }
        else if ratio < 0.93 { m.penalise(1.5, "Some notes leave \(key.name): \(outsideText). Keep them only as passing notes.") }
        if !bass.isEmpty && !chords.isEmpty {
            let agreement = bassAgreement(bass: bass, harmony: chords)
            if agreement < 0.5 { m.penalise(3, "The bass plays chord tones only \(Int(agreement * 100))% of the time. Follow the chord roots.") }
            else if agreement < 0.65 { m.penalise(2, "The bass agrees with the chords \(Int(agreement * 100))% of the time. Land on roots and fifths on strong beats.") }
            else if agreement < 0.8 { m.penalise(1, "The bass agrees with the chords \(Int(agreement * 100))% of the time. Tighten it on the downbeats.") }
        }
        let chordSets = Set(Dictionary(grouping: chords) { Int($0.begin * 2) }.values.map { Set($0.compactMap(\.midi).map(MusicTheory.pitchClass)) })
        if !chords.isEmpty && chordSets.count < 3 { m.penalise(2, "The harmony barely moves. Use a progression of at least 4 chords.") }
        return m
    }

    /// Share of bass onsets whose pitch class is in the chord sounding at that moment.
    public static func bassAgreement(bass: [NoteEvent], harmony: [NoteEvent]) -> Double {
        var checked = 0, agreed = 0
        for note in bass {
            guard let midi = note.midi else { continue }
            let sounding = harmony.filter { $0.begin <= note.begin && note.begin < $0.end }.compactMap(\.midi)
            guard !sounding.isEmpty else { continue }
            checked += 1
            if Set(sounding.map(MusicTheory.pitchClass)).contains(MusicTheory.pitchClass(midi)) { agreed += 1 }
        }
        return checked == 0 ? 1 : Double(agreed) / Double(checked)
    }
}
