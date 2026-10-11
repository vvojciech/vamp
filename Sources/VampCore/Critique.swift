import Foundation

/// A second model judges the song like a producer would, with the measured scores as evidence.
public enum Critique {
    public struct Judged: Sendable {
        public var card: Scorecard
        public var verdict: String
    }

    private struct Reply: Decodable {
        var verdict: String
        var aspects: [Aspect]
    }

    public static func decode(_ data: Data) throws -> Judged {
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return Judged(card: Scorecard(aspects: reply.aspects), verdict: reply.verdict)
    }

    public static let system = """
    You are a strict music producer reviewing a song made in Strudel, a live-coding language. You \
    cannot hear it, so read the code like a score: notes, chords, rhythm, sounds, effects, levels and \
    the arrangement of sections. Score each aspect from 0 to 10 against released music in the same \
    genre. 9 means you would release it. 7 means competent but forgettable. Do not be generous: \
    a loop, a static chord, a plain four-on-the-floor or a raw oscillator never reaches 9.
    The song must be complete and radio length: 3:00 to 4:00, with a real beginning, a development \
    and a real ending that resolves. A loop, a sketch or a song under 3:00 never scores above 6 on form.
    Aspects: form (complete song, radio length, sections, contrast), energy (build, release, peak), harmony (key, \
    progression, voice leading, bass against chords), groove (drum programming, syncopation, fills, \
    dynamics), melody (a hook, its shape, its development), sound (sound choice, envelopes, filters, \
    space, movement), mix (levels, registers, stereo, clutter).
    STRUDEL FACTS. .voicing() already voice-leads chords smoothly around .anchor(). Named samples \
    are real recordings (piano is a Steinway, banks such as LinnDrum and RolandTR909 are those drum \
    machines). Sounds named gm_... are General MIDI soundfont instruments (electric pianos, strings, \
    brass, choirs, pads, leads), richer than raw oscillators. .duckorbit(n) on the kick sidechains every \
    layer on .orbit(n). Voices exist only as choir and ooh sounds (gm_choir_aahs, gm_voice_oohs), the \
    only reversed sound is gm_reverse_cymbal, and the only EQ is lpf, hpf and bpf. Only suggest changes \
    Strudel can do.
    The MEASURED scores come from analysis of the actual notes. Never score an aspect higher than \
    its measured score plus 1. Write notes only for problems a listener would notice, at most 3 per \
    aspect, most important first. Each note is one concrete change that names the layer or section \
    and what to write, for example "Chorus 2: give Lead a variation that lifts the motif an octave". \
    When an aspect has no real problem left, give it 9 or 10 and no notes. Write a one-sentence verdict.
    """

    public static func prompt(song: Song, measured: Scorecard) -> String {
        let length = song.durationSeconds.map { "\(Song.clock($0)) (\(song.totalBars ?? 0) bars at \(Int(song.bpm)) BPM)" }
            ?? "a loop with no sections"
        return "SONG\n\(AgentPrompt.songJSON(song))\n\nLENGTH\n\(length)\n\nMEASURED\n\(measured.report)\n\nReview the song."
    }

    public static let jsonSchema = """
    {"type":"object","additionalProperties":false,"required":["verdict","aspects"],"properties":{\
    "verdict":{"type":"string"},\
    "aspects":{"type":"array","items":{"type":"object","additionalProperties":false,\
    "required":["name","score","notes"],"properties":{\
    "name":{"type":"string","enum":["form","energy","harmony","groove","melody","sound","mix"]},\
    "score":{"type":"number"},\
    "notes":{"type":"array","items":{"type":"string"}}}}}}}
    """

    /// The request the editing agent gets for a revision round.
    /// Asks for a focused revision: fix the two weakest aspects completely, keep everything else.
    /// Fixing every note at once tends to add layers and break the mix.
    public static func revisionRequest(card: Scorecard, goal: Double, verdict: String) -> String {
        let weakest = card.aspects.filter { $0.score < goal }.sorted { $0.score < $1.score }
        let now = Scorecard(aspects: Array(weakest.prefix(2)))
        let later = Scorecard(aspects: Array(weakest.dropFirst(2)))
        let strong = card.aspects.filter { $0.score >= goal }.map(\.name.label)
        let protect = strong.isEmpty ? "" : "\nDo not make these worse: \(strong.joined(separator: ", ")).\n"
        return """
        Revise this song so that the aspects in the first list reach \(String(format: "%.0f", goal)) or more. Fix \
        them completely, and change nothing that they do not need. The second list is context only: \
        do not act on it in this round, but do not make those aspects worse.
        Improve existing layers and section variations before you add layers. Add a layer only when no \
        existing one can do the job, and then lower or remove another one in that section. Keep at most \
        8 layers in any section and the sum of gains under 4. Give reverb and delay to at most three layers.
        \(protect)
        VERDICT
        \(verdict)

        FIX NOW
        \(now.report)

        FOR LATER
        \(later.report.isEmpty ? "Nothing." : later.report)
        """
    }
}

/// Runs measure, judge and revise rounds until the song reaches the goal or the rounds run out.
/// Each revision starts from the best song so far, so a worse revision is discarded, not built on.
public enum Polisher {
    /// Measured spread of an averaged review: about half a point per aspect.
    public static let noiseMargin = 0.5

    public struct Assessment: Sendable {
        public var card: Scorecard
        public var verdict: String
        public init(card: Scorecard, verdict: String) {
            self.card = card
            self.verdict = verdict
        }
    }

    public struct Round: Sendable {
        public var number: Int
        public var song: Song
        public var card: Scorecard
        public var verdict: String
    }

    public struct Result: Sendable {
        public var rounds: [Round]
        /// The highest-scoring round. A later revision can make things worse.
        public var best: Round { rounds.max { $0.card.overall < $1.card.overall || ($0.card.overall == $1.card.overall && $0.number > $1.number) }! }
    }

    public static func run(
        song: Song, goal: Double, maxRounds: Int,
        revise: @Sendable (String, Song) async throws -> Song,
        assess: @Sendable (Song) async throws -> Assessment,
        progress: @Sendable (Round) async -> Void
    ) async throws -> Result {
        var current = song
        var rounds: [Round] = []
        for number in 1...(maxRounds + 1) {
            try Task.checkCancellation()
            let assessment = try await assess(current)
            let round = Round(number: number, song: current, card: assessment.card, verdict: assessment.verdict)
            rounds.append(round)
            await progress(round)
            if round.card.overall >= goal || number > maxRounds { break }
            // A clear drop goes back to the best song. A difference within the judges' noise
            // builds on the latest one, so an early lucky score does not anchor every revision.
            let best = Result(rounds: rounds).best
            let base = best.card.overall - round.card.overall <= noiseMargin ? round : best
            current = try await revise(Critique.revisionRequest(card: base.card, goal: goal, verdict: base.verdict), base.song)
        }
        return Result(rounds: rounds)
    }
}
