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
    Aspects: form (sections, length, contrast), energy (build, release, peak), harmony (key, \
    progression, voice leading, bass against chords), groove (drum programming, syncopation, fills, \
    dynamics), melody (a hook, its shape, its development), sound (sound choice, envelopes, filters, \
    space, movement), mix (levels, registers, stereo, clutter).
    STRUDEL FACTS. .voicing() already voice-leads chords smoothly around .anchor(). Named samples \
    are real recordings (piano is a Steinway, banks such as LinnDrum and RolandTR909 are those drum \
    machines). .duckorbit(n) on the kick sidechains every layer on .orbit(n). Strudel has no vocals, \
    no reversed audio and no EQ bands beyond lpf, hpf and bpf. Only suggest changes Strudel can do.
    The MEASURED scores come from analysis of the actual notes. Never score an aspect higher than \
    its measured score plus 1. Write notes only for problems a listener would notice, at most 3 per \
    aspect, most important first. Each note is one concrete change that names the layer or section \
    and what to write, for example "Chorus 2: give Lead a variation that lifts the motif an octave". \
    When an aspect has no real problem left, give it 9 or 10 and no notes. Write a one-sentence verdict.
    """

    public static func prompt(song: Song, measured: Scorecard) -> String {
        "SONG\n\(AgentPrompt.songJSON(song))\n\nMEASURED\n\(measured.report)\n\nReview the song."
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
    public static func revisionRequest(card: Scorecard, goal: Double, verdict: String) -> String {
        let strong = card.aspects.filter { $0.score >= goal }.map(\.name.label)
        let protect = strong.isEmpty ? "" : "\nDo not make these worse: \(strong.joined(separator: ", ")). Leave the layers that carry them alone unless a fix needs them.\n"
        return """
        Improve this song until every aspect scores \(String(format: "%.0f", goal)) or more. Fix the weakest \
        aspects first. You may add, rewrite or remove layers and sections, and use section variations. \
        Make every change the critique asks for that fits the song, and check that each change does not \
        create a new problem (for example, a new layer raises the total gain).
        \(protect)
        VERDICT
        \(verdict)

        CRITIQUE
        \(card.report)
        """
    }
}

/// Runs measure, judge and revise rounds until the song reaches the goal or the rounds run out.
/// Each revision starts from the best song so far, so a worse revision is discarded, not built on.
public enum Polisher {
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
            let best = Result(rounds: rounds).best
            current = try await revise(Critique.revisionRequest(card: best.card, goal: goal, verdict: best.verdict), best.song)
        }
        return Result(rounds: rounds)
    }
}
