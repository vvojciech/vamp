import Foundation
import VampCore

/// The polish loop: measure and judge the song, revise it with the critique, repeat until
/// every aspect reaches the goal. The best round wins, because a revision can make things worse.
extension AppModel {
    var isPolishing: Bool { chat.last?.rounds != nil && chat.last?.state == .working }

    func polish(goal: Double = 9, maxRounds: Int = 4) {
        guard !isAgentWorking, !song.layers.isEmpty else { return }
        let kind = backend
        var entry = ChatEntry(request: "Polish until every aspect scores \(Int(goal)) or more",
                              backend: "\(kind.displayName(model: kind.composerModel)), judged by \(kind.displayName(model: kind.judgeModel))",
                              songBefore: song)
        entry.rounds = []
        chat.append(entry)
        let started = Date()

        agentTask = Task {
            do {
                let result = try await Polisher.run(
                    song: song, goal: goal, maxRounds: maxRounds,
                    revise: { request, current in try await self.revise(request, current, kind: kind) },
                    assess: { current in try await self.assess(current, kind: kind) },
                    progress: { round in await self.record(round) })
                let best = result.best
                update { $0 = best.song }
                scorecard = best.card
                scorecardJudged = true
                updateLastEntry { entry in
                    entry.state = .done
                    let weakest = best.card.aspects.min { $0.score < $1.score }
                    let reached = best.card.overall >= goal
                    entry.summary = (reached ? "Every aspect is \(Int(goal)) or more" : "Best result")
                        + " after round \(best.number): lowest is \(weakest?.name.label ?? "") at \(String(format: "%.1f", best.card.overall)). "
                        + best.verdict
                }
            } catch is CancellationError {
                updateLastEntry { $0.state = .failed("Stopped. The song keeps the last revision.") }
            } catch {
                updateLastEntry { $0.state = .failed(error.localizedDescription) }
            }
            updateLastEntry { $0.seconds = Date().timeIntervalSince(started) }
            scheduleSave()
        }
    }

    private func revise(_ request: String, _ current: Song, kind: BackendKind) async throws -> Song {
        let result = try await AgentSession.run(
            request: request, song: current, history: [],
            ask: { system, user in
                try await Backends.ask(BackendRequest(kind: kind, model: kind.composerModel, system: system, user: user,
                                                      effort: "high", timeout: 900))
            },
            validate: { [weak self] candidate in
                guard let self else { return [:] }
                let found = await self.analyze(candidate, cycles: candidate.totalBars ?? 4)
                return found.compactMapValues { if case let .failure(e) = $0 { e.message } else { nil } }
            })
        update { $0 = result.song }  // Play each revision, so the musician hears the progress.
        updateLastEntry { entry in
            entry.tokens += result.inputTokens + result.outputTokens
            if let cost = result.costUSD, kind == .anthropicAPI { entry.costUSD = (entry.costUSD ?? 0) + cost }
        }
        return result.song
    }

    private func assess(_ current: Song, kind: BackendKind) async throws -> Polisher.Assessment {
        let bars = current.totalBars ?? self.bars
        let events = await analyze(current, cycles: bars).compactMapValues { try? $0.get() }
        let measured = SongCritic.measure(song: current, events: events, bars: bars)
        // Two independent reviews in parallel. One review varies by about half a point per
        // aspect, and the overall score is the lowest aspect, so a single review chases noise.
        let request = BackendRequest(kind: kind, model: kind.judgeModel, system: Critique.system,
                                     user: Critique.prompt(song: current, measured: measured),
                                     schema: Critique.jsonSchema, effort: "medium", timeout: 600)
        async let first = Backends.ask(request)
        async let second = Backends.ask(request)
        let replies = try await [first, second]
        let judged = try replies.map { try Critique.decode($0.json) }
        updateLastEntry { entry in
            for reply in replies {
                entry.tokens += reply.inputTokens + reply.outputTokens
                if let cost = reply.costUSD, kind == .anthropicAPI { entry.costUSD = (entry.costUSD ?? 0) + cost }
            }
        }
        let card = Scorecard.averaged(judged.map(\.card))
        return Polisher.Assessment(card: measured.combined(with: card), verdict: judged[0].verdict)
    }

    private func record(_ round: Polisher.Round) {
        scorecard = round.card
        scorecardJudged = true
        let weakest = round.card.aspects.min { $0.score < $1.score }?.name.label ?? ""
        updateLastEntry { $0.rounds?.append(RoundNote(number: round.number, overall: round.card.overall, weakest: weakest)) }
        scheduleSave()
    }
}

extension BackendKind {
    /// The model that writes and revises whole songs. Quality matters more than speed here.
    var composerModel: String {
        switch self {
        case .claudeCLI: "opus"
        case .codexCLI: ""
        case .anthropicAPI: APIModel.opus.rawValue
        }
    }

    /// The model that judges. Opus measured more consistent than Sonnet (about ±0.5 against ±1 per
    /// aspect on the same song). It sees only the code, and the measured critic caps every aspect.
    var judgeModel: String {
        switch self {
        case .claudeCLI: "opus"
        case .codexCLI: ""
        case .anthropicAPI: APIModel.opus.rawValue
        }
    }
}
