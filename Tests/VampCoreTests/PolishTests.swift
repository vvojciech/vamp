import Foundation
import Testing
@testable import VampCore

private func card(_ score: Double) -> Scorecard {
    Scorecard(aspects: AspectName.allCases.map { Aspect(name: $0, score: $0 == .melody ? score : 9.5, notes: ["melody note"]) })
}

private actor Log {
    var requests: [String] = []
    var rounds: [Int] = []
    func add(_ r: String) { requests.append(r) }
    func round(_ n: Int) { rounds.append(n) }
}

@Suite struct PolishTests {
    @Test func judgeReplyDecodesIntoAScorecard() throws {
        let json = #"{"verdict":"Close.","aspects":[{"name":"melody","score":7.5,"notes":["Bring the hook back in the chorus."]}]}"#
        let judged = try Critique.decode(Data(json.utf8))
        #expect(judged.card.score(.melody) == 7.5)
        #expect(judged.verdict == "Close.")
    }

    @Test func judgeRubricAnchorsTheScaleAndSeparatesProblemsFromPolish() {
        #expect(Critique.system.contains("9: release-ready"))
        #expect(Critique.system.contains("\"Problem:\"") && Critique.system.contains("\"Polish:\""))
        #expect(Critique.system.contains("an aspect with no Problem notes scores 9 or 10"))
    }

    @Test func judgeSchemaListsEveryAspect() throws {
        let object = try JSONSerialization.jsonObject(with: Data(Critique.jsonSchema.utf8)) as? [String: Any]
        let text = String(describing: object)
        for name in AspectName.allCases { #expect(text.contains(name.rawValue)) }
    }

    @Test func stopsAsSoonAsEveryAspectReachesTheGoal() async throws {
        let log = Log()
        let scores = [7.0, 9.2]
        let counter = Counter()
        let result = try await Polisher.run(
            song: .starter, goal: 9, maxRounds: 4,
            revise: { request, song in await log.add(request); return song },
            assess: { _ in Polisher.Assessment(card: card(scores[await counter.next()]), verdict: "v") },
            progress: { round in await log.round(round.number) })
        #expect(result.rounds.count == 2)
        #expect(result.rounds.last?.card.overall == 9.2)
        #expect(await log.requests.count == 1)
        #expect(await log.requests.first?.contains("melody note") == true)
    }

    @Test func givesUpAfterMaxRoundsAndReportsTheBest() async throws {
        let counter = Counter()
        let scores = [6.0, 8.0, 7.0, 7.5]
        let result = try await Polisher.run(
            song: .starter, goal: 9, maxRounds: 3,
            revise: { _, song in var s = song; s.title += "!"; return s },
            assess: { _ in Polisher.Assessment(card: card(scores[await counter.next()]), verdict: "v") },
            progress: { _ in })
        #expect(result.rounds.count == 4)
        #expect(result.best.card.overall == 8.0)
        #expect(result.best.song.title == "Night Drive!")
    }
}

@Suite struct PolishFromBestTests {
    @Test func aWorseRoundIsDiscardedAndTheNextRevisionStartsFromTheBest() async throws {
        let counter = Counter()
        let seen = Log()
        let scores = [6.0, 8.0, 7.0, 9.1]
        let result = try await Polisher.run(
            song: .starter, goal: 9, maxRounds: 3,
            revise: { request, song in
                await seen.add(song.title)
                var next = song
                next.title = "v\(await counter.value + 1)"
                return next
            },
            assess: { _ in Polisher.Assessment(card: card(scores[await counter.next()]), verdict: "v") },
            progress: { _ in })
        // Round 2 (v1) scored 8; round 3 (v2) scored 7, so round 4 revises v1 again.
        #expect(await seen.requests == ["Night Drive", "v1", "v1"])
        #expect(result.best.card.overall == 9.1)
    }

    @Test func aRoundWithinTheNoiseMarginOfTheBestIsBuiltOn() async throws {
        let counter = Counter()
        let seen = Log()
        let scores = [8.0, 7.6, 9.2]
        _ = try await Polisher.run(
            song: .starter, goal: 9, maxRounds: 3,
            revise: { _, song in
                await seen.add(song.title)
                var next = song
                next.title = "v\(await counter.value + 1)"
                return next
            },
            assess: { _ in Polisher.Assessment(card: card(scores[await counter.next()]), verdict: "v") },
            progress: { _ in })
        // 7.6 is within 0.5 of 8.0, so the second revision starts from v1, not the original.
        #expect(await seen.requests == ["Night Drive", "v1"])
    }

    @Test func revisionRequestProtectsStrongAspectsAndCarriesTheVerdict() {
        let text = Critique.revisionRequest(card: card(7), goal: 9, verdict: "Close, but the hook is weak.")
        #expect(text.contains("Close, but the hook is weak."))
        #expect(text.contains("Do not make these worse: Form"))
    }

    @Test func revisionFixesEveryProblemAndLeavesPolishAsContext() {
        let card = Scorecard(aspects: [
            .init(name: .mix, score: 6.8, notes: ["Problem: The pad masks the lead.", "Polish: Pan the hats wider."]),
            .init(name: .groove, score: 7.5, notes: ["Problem: Verse and chorus drums are the same."]),
            .init(name: .melody, score: 8, notes: ["The melody spans only 5 semitones."]),  // measured notes have no label
            .init(name: .form, score: 9.2, notes: ["Polish: Add a crash on the final downbeat."]),
        ])
        let text = Critique.revisionRequest(card: card, goal: 9, verdict: "v")
        let fix = text.components(separatedBy: "PROBLEMS TO FIX")[1].components(separatedBy: "OPTIONAL POLISH")[0]
        #expect(fix.contains("The pad masks the lead.") && fix.contains("Verse and chorus drums are the same."))
        #expect(fix.contains("The melody spans only 5 semitones."))
        #expect(!fix.contains("Pan the hats wider."))
        let polish = text.components(separatedBy: "OPTIONAL POLISH")[1]
        #expect(polish.contains("Pan the hats wider.") && polish.contains("Add a crash on the final downbeat."))
    }
}

private actor Counter {
    var value = -1
    func next() -> Int { value += 1; return value }
}
