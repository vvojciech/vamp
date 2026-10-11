import Foundation
import VampCore

extension AppModel {
    var isAgentWorking: Bool { chat.last?.state == .working }
    var sessionCost: Double { chat.compactMap(\.costUSD).reduce(0, +) }

    func send(_ request: String) {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAgentWorking else { return }
        let kind = backend, chosen = model
        chat.append(ChatEntry(request: text, backend: kind.displayName(model: chosen), songBefore: song))
        let history = chat.filter { $0.state == .done }.map { Turn(request: $0.request, summary: $0.summary) }
        let started = Date()

        agentTask = Task {
            do {
                let result = try await AgentSession.run(
                    request: text, song: song, history: history,
                    ask: { system, user in try await Backends.ask(kind: kind, model: chosen, system: system, user: user) },
                    validate: { [weak self] candidate in
                        guard let self else { return [:] }
                        let found = await self.analyze(candidate, cycles: candidate.totalBars ?? 4)
                        return found.compactMapValues { if case let .failure(e) = $0 { e.message } else { nil } }
                    })
                update { $0 = result.song }
                finishEntry { entry in
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
                finishEntry { $0.state = .failed("Stopped.") }
            } catch {
                finishEntry { $0.state = .failed(error.localizedDescription) }
            }
            finishEntry { $0.seconds = Date().timeIntervalSince(started) }
            scheduleSave()
        }
    }

    func cancelAgent() { agentTask?.cancel() }

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

    private func finishEntry(_ change: (inout ChatEntry) -> Void) {
        guard !chat.isEmpty else { return }
        change(&chat[chat.count - 1])
    }
}
