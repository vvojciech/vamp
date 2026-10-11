import Foundation

extension SongCritic {
    // MARK: Groove

    public static func groove(drums: [NoteEvent], bars: Int, sectionStarts: [Int]) -> Measured {
        var m = Measured()
        guard !drums.isEmpty else {
            m.penalise(7, "No drums or percussion. Add a beat, even a soft one.")
            return m
        }
        let sounds = Set(drums.compactMap { $0.sound?.split(separator: ":").first.map(String.init) })
        if sounds.count <= 2 { m.penalise(2, "Only \(sounds.count) drum sounds. Use kick, snare or clap, closed and open hats, and a percussion accent.") }
        else if sounds.count == 3 { m.penalise(1, "Add a fourth drum sound, such as an open hat, a rim or a shaker.") }

        let offbeat = Double(drums.filter { ($0.begin * 4).truncatingRemainder(dividingBy: 1) > 0.01 }.count) / Double(drums.count)
        if offbeat < 0.15 { m.penalise(2, "The beat sits on the quarter notes. Add off-beat hats, ghost notes or swing.") }
        else if offbeat < 0.3 { m.penalise(1, "Add more off-beat hits for a stronger groove.") }

        // One signature per bar: which sound hits on which 16th.
        var signatures: [Int: Set<String>] = [:]
        for hit in drums {
            let bar = Int(hit.begin)
            let step = Int(((hit.begin - Double(bar)) * 16).rounded())
            signatures[bar, default: []].insert("\(hit.sound ?? "")@\(step)")
        }
        if Set(signatures.values).count == 1 && bars > 2 {
            m.penalise(2, "Every bar has the same drum pattern. Add fills at the end of sections and vary the hats.")
        } else if sectionStarts.count > 1 || bars >= 8 {
            let ends = (sectionStarts.dropFirst() + [bars]).map { $0 - 1 }
            let fills = ends.filter { end in signatures[end] != nil && signatures[end] != signatures[end - 1] }.count
            if fills * 2 < ends.count { m.penalise(1, "Few sections end with a fill. Change the drums in the last bar of a section.") }
        }
        if Set(drums.map(\.gain)).count < 2 { m.penalise(1, "All hits have the same volume. Accent with gain patterns or velocity.") }
        return m
    }

    // MARK: Melody

    public static func melody(_ line: [NoteEvent]) -> Measured {
        var m = Measured()
        let notes = line.filter { $0.midi != nil }.sorted { $0.begin < $1.begin }
        guard notes.count >= 8 else {
            m.penalise(8, "There is no melody or hook. Add a lead or arp layer with a short motif that comes back.")
            return m
        }
        let pitches = notes.compactMap(\.midi)
        let range = (pitches.max() ?? 0) - (pitches.min() ?? 0)
        if range < 7 { m.penalise(2, "The melody spans only \(Int(range)) semitones. Give it a wider shape, up to an octave or more.") }
        else if range < 10 { m.penalise(1, "The melody spans \(Int(range)) semitones. Reach a little higher at the peak.") }

        let intervals = zip(pitches, pitches.dropFirst()).map { Int(($1 - $0).rounded()) }
        if intervals.count >= 4 {
            let grams = (0...(intervals.count - 4)).map { intervals[$0..<($0 + 4)].map(String.init).joined(separator: ",") }
            let uniqueness = Double(Set(grams).count) / Double(grams.count)
            if uniqueness < 0.15 { m.penalise(2, "The melody repeats one figure. Answer the motif and vary it in later sections.") }
            else if uniqueness > 0.85 { m.penalise(2, "The melody never repeats, so there is no hook. State a short motif and bring it back.") }
        }
        let durations = Set(notes.map { (($0.end - $0.begin) * 64).rounded() })
        if durations.count < 2 { m.penalise(1, "Every melody note has the same length. Mix short and long notes.") }
        return m
    }

    // MARK: Sound design

    static let effects = ["room", "size", "delay", "delaytime", "delayfeedback", "lpf", "hpf", "bpf", "lpq", "attack", "decay",
                          "sustain", "release", "lpenv", "lpattack", "lpdecay", "distort", "shape", "crush", "coarse", "phaser",
                          "vowel", "pan", "vib", "fm", "compressor", "velocity", "orbit", "tremolo", "chorus"]

    public static func soundDesign(_ song: Song) -> Measured {
        var m = Measured()
        guard !song.layers.isEmpty else {
            m.penalise(10, "The song has no layers.")
            return m
        }
        let codes = song.layers.map { layer in ([layer.code] + song.sections.compactMap { $0.variations[layer.id] }).joined(separator: "\n") }
        let all = codes.joined(separator: "\n")

        var sources = Set<String>()
        for match in all.matches(of: #/(?:\bs|\.s|\.bank)\(\s*"([^"]*)"/#) {
            sources.formUnion(String(match.1).split { " ,[]<>*!@~:".contains($0) || $0.isNumber }.map(String.init))
        }
        if sources.count < 4 { m.penalise(2, "Only \(sources.count) sound sources. Use a richer palette: a drum-machine bank, piano or mallets, a synth bass, a pad.") }
        else if sources.count < 6 { m.penalise(1, "Add one or two more distinct sounds.") }

        let perLayer = codes.map { code in Set(effects.filter { code.contains(".\($0)(") }).count }
        let average = Double(perLayer.reduce(0, +)) / Double(perLayer.count)
        if average < 1 { m.penalise(3, "Layers are dry and raw. Shape each one with filters, envelopes, reverb or delay.") }
        else if average < 1.8 { m.penalise(1, "Shape more layers with envelopes, filters and space.") }

        if all.firstMatch(of: #/\b(sine|cosine|saw|tri|perlin|rand|square)\.(range|slow|segment)/#) == nil && !all.contains("perlin") {
            m.penalise(1, "Nothing moves over time. Sweep a filter or pan with sine.range(...).slow(8).")
        }
        let rich = ["bank(", "piano", "supersaw", "vibraphone", "marimba", "kalimba", "harp", "glockenspiel", "steinway",
                    "sax", "organ", "fmpiano", "wineglass", "tubularbells", "xylophone", "jvbass", "juno", "moog"]
        if !rich.contains(where: all.contains) { m.penalise(1, "The palette is only raw oscillators. Bring in a drum machine bank, piano or mallet samples.") }
        if !all.contains(".pan(") && !all.contains(".jux(") && !all.contains("juxBy(") {
            m.penalise(1, "Everything sits in the centre. Pan hats and percussion, or use jux on the arp.")
        }
        return m
    }

    // MARK: Mix

    public static func mix(_ song: Song, events: [String: [NoteEvent]], sections: [(Range<Int>, [String])]) -> Measured {
        var m = Measured()
        for layer in song.layers where layer.gain > 1.2 {
            m.penalise(1, "\(layer.name) is too loud (\(Int(layer.gain * 100))%). Keep layer volumes at 120% or less.")
        }
        for (range, ids) in sections {
            let load = song.layers.filter { ids.contains($0.id) }.map(\.gain).reduce(0, +)
            if load > 4 { m.penalise(1, "Bars \(range.lowerBound + 1) to \(range.upperBound) stack \(String(format: "%.1f", load)) of gain and may clip. Lower the pads and chords.") }
        }
        func median(_ role: LayerRole) -> Double? {
            let pitches = song.layers.filter { $0.role == role }.flatMap { events[$0.id] ?? [] }.compactMap(\.midi).sorted()
            return pitches.isEmpty ? nil : pitches[pitches.count / 2]
        }
        if let bass = median(.bass), bass > 52 { m.penalise(1, "The bass sits high (around \(MusicTheory.pitchNames[MusicTheory.pitchClass(bass)])\(Int(bass) / 12 - 1)). Move it to octave 1 or 2.") }
        let lead = median(.lead) ?? median(.arp)
        let pad = median(.pad) ?? median(.chords)
        if let lead, let pad, abs(lead - pad) < 4 { m.penalise(1, "The melody and the chords share one register and mask each other. Move the melody up an octave.") }
        for layer in song.layers where [.drums, .bass].contains(layer.role) && layer.gain < 0.5 {
            m.penalise(1, "\(layer.name) is quiet (\(Int(layer.gain * 100))%). Drums and bass carry the groove.")
        }
        let wet = song.layers.filter { $0.code.firstMatch(of: #/\.room\(\s*0?\.[6-9]/#) != nil || $0.code.contains(".room(1") }
        if wet.count * 2 > song.layers.count && song.layers.count > 2 { m.penalise(1, "Most layers have heavy reverb, which muddies the mix. Keep drums and bass drier.") }
        return m
    }
}
