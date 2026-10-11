import Foundation
import VampCore

extension AppModel {
    var isAgentWorking: Bool { chat.last?.state == .working }
    var sessionCost: Double { chat.compactMap(\.costUSD).reduce(0, +) }

    func send(_ request: String) {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAgentWorking else { return }
        let kind = backend
        // Quick edits use the chosen model; a whole song is worth the composer model.
        let big = Self.isBigRequest(text)
        let chosen = big ? kind.composerModel : model
        chat.append(ChatEntry(request: text, backend: kind.displayName(model: chosen), songBefore: song))
        let history = chat.filter { $0.state == .done }.map { Turn(request: $0.request, summary: $0.summary) }
        let started = Date()

        agentTask = Task {
            do {
                let result = try await AgentSession.run(
                    request: text, song: song, history: history,
                    ask: { system, user in
                        try await Backends.ask(BackendRequest(kind: kind, model: chosen, system: system, user: user,
                                                              effort: big ? "high" : "low", timeout: big ? 900 : 300))
                    },
                    validate: { [weak self] candidate in
                        guard let self else { return [:] }
                        let found = await self.analyze(candidate, cycles: candidate.totalBars ?? 4)
                        return found.compactMapValues { if case let .failure(e) = $0 { e.message } else { nil } }
                    })
                update { $0 = result.song }
                updateLastEntry { entry in
                    entry.state = .done
                    entry.summary = result.summary
                    entry.changes = result.changes
                    // CLI backends report list-price figures, but the plan pays, so only the API shows dollars.
                    entry.costUSD = kind == .anthropicAPI ? result.costUSD : nil
                    entry.tokens = result.inputTokens + result.outputTokens
                    entry.attempts = result.attempts
                }
                focus(on: result.changes)
            } catch is CancellationError {
                updateLastEntry { $0.state = .failed("Stopped.") }
            } catch {
                updateLastEntry { $0.state = .failed(error.localizedDescription) }
            }
            updateLastEntry { $0.seconds = Date().timeIntervalSince(started) }
            scheduleSave()
        }
    }

    func cancelAgent() { agentTask?.cancel() }

    /// A request for a whole song gets more thinking than a quick tweak.
    nonisolated static func isBigRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["compose", "write a song", "full song", "whole song", "new song", "arrange"].contains(where: lower.contains)
    }

    /// Puts the song back to how it was before this prompt.
    func revert(_ entry: ChatEntry) { update { $0 = entry.songBefore } }

    func clearChat() {
        chat.removeAll { $0.state != .working }
        scheduleSave()
    }

    /// Selects what the agent just made, so the musician sees it at once.
    private func focus(on changes: [EditPlan.Change]) {
        for change in changes {
            switch change {
            case let .sectionAdded(id):
                selectedSectionID = id
                inspectsSection = true
                return
            case let .added(id):
                selectedLayerID = id
                return
            default: continue
            }
        }
    }

    func updateLastEntry(_ change: (inout ChatEntry) -> Void) {
        guard !chat.isEmpty else { return }
        change(&chat[chat.count - 1])
    }
}
