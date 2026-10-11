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
    The MEASURED scores come from analysis of the actual notes. Never score an aspect higher than \
    its measured score plus 1. For each aspect write up to 3 notes. Each note is one concrete change \
    that names the layer or section and what to write, for example "Chorus: give Lead a variation \
    that lifts the motif an octave". Write a one-sentence verdict.
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
    public static func revisionRequest(card: Scorecard, goal: Double) -> String {
        """
        Improve this song until every aspect scores \(String(format: "%.0f", goal)) or more. Fix the weakest \
        aspects first and keep what already works. You may add, rewrite or remove layers and sections, \
        and use section variations. Make every change the critique asks for that fits the song.

        CRITIQUE
        \(card.report)
        """
    }
}

/// Runs measure, judge and revise rounds until the song reaches the goal or the rounds run out.
public enum Polisher {
    public struct Round: Sendable {
        public var number: Int
        public var song: Song
        public var card: Scorecard
    }

    public struct Result: Sendable {
        public var rounds: [Round]
        /// The highest-scoring round. A later revision can make things worse.
        public var best: Round { rounds.max { $0.card.overall < $1.card.overall || ($0.card.overall == $1.card.overall && $0.number > $1.number) }! }
    }

    public static func run(
        song: Song, goal: Double, maxRounds: Int,
        revise: @Sendable (String, Song) async throws -> Song,
        assess: @Sendable (Song) async throws -> Scorecard,
        progress: @Sendable (Round) async -> Void
    ) async throws -> Result {
        var current = song
        var rounds: [Round] = []
        for number in 1...(maxRounds + 1) {
            try Task.checkCancellation()
            let round = Round(number: number, song: current, card: try await assess(current))
            rounds.append(round)
            await progress(round)
            if round.card.overall >= goal || number > maxRounds { break }
            current = try await revise(Critique.revisionRequest(card: round.card, goal: goal), current)
        }
        return Result(rounds: rounds)
    }
}
