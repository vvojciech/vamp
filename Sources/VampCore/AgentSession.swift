import Foundation

public enum AgentError: Error, LocalizedError {
    case invalidPlan(String)
    case rejected([String: String])

    public var errorDescription: String? {
        switch self {
        case let .invalidPlan(detail): "The agent sent a plan Vamp could not read. \(detail)"
        case let .rejected(errors):
            "The agent's code did not run after two tries: " + errors.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        }
    }
}

public struct AgentResult: Sendable {
    public var song: Song
    public var summary: String
    public var changes: [EditPlan.Change]
    public var costUSD: Double?
    public var inputTokens: Int
    public var outputTokens: Int
    public var attempts: Int
}

/// One prompt from the musician: ask the backend, apply the plan, check it in Strudel,
/// and ask once more with the errors if the code does not run.
public enum AgentSession {
    public typealias Ask = @Sendable (_ system: String, _ user: String) async throws -> BackendReply
    /// Returns an error message per layer id. An empty result means every layer runs.
    public typealias Validate = @Sendable (_ song: Song) async -> [String: String]

    public static let maxAttempts = 2

    public static func run(request: String, song: Song, history: [Turn], ask: Ask, validate: Validate) async throws -> AgentResult {
        let original = AgentPrompt.user(request: request, song: song, history: history)
        var prompt = original
        var cost: Double?
        var tokens = (input: 0, output: 0)
        var lastErrors: [String: String] = [:]

        for attempt in 1...maxAttempts {
            let reply = try await ask(AgentPrompt.system, prompt)
            if let replyCost = reply.costUSD { cost = (cost ?? 0) + replyCost }
            tokens.input += reply.inputTokens
            tokens.output += reply.outputTokens

            let plan: EditPlan
            do { plan = try JSONDecoder().decode(EditPlan.self, from: reply.json) }
            catch { throw AgentError.invalidPlan(error.localizedDescription) }

            var next = song
            var changes: [EditPlan.Change] = []
            var errors: [String: String] = [:]
            for edit in plan.edits {
                do { changes.append(try edit.apply(to: &next)) }
                catch { errors[edit.layerID ?? edit.op.rawValue] = error.localizedDescription }
            }
            let touched = Set(changes.compactMap(\.layerID))
            let codeErrors = await validate(next).filter { touched.contains($0.key) }
            errors.merge(codeErrors) { first, _ in first }

            if errors.isEmpty {
                return AgentResult(song: next, summary: plan.summary, changes: changes, costUSD: cost,
                                   inputTokens: tokens.input, outputTokens: tokens.output, attempts: attempt)
            }
            lastErrors = errors
            prompt = AgentPrompt.repair(original: original, plan: plan, errors: errors)
        }
        throw AgentError.rejected(lastErrors)
    }
}

public extension EditPlan.Change {
    var layerID: String? {
        switch self {
        case let .added(id), let .changed(id): id
        case .removed, .tempo, .title, .sectionAdded, .sectionChanged, .sectionRemoved: nil
        }
    }
}
