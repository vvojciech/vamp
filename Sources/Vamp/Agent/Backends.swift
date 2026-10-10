import Foundation
import VampCore

/// Where the agent's thinking happens. The two CLI backends use the musician's own subscription.
enum BackendKind: String, CaseIterable, Identifiable, Codable {
    case claudeCLI, codexCLI, anthropicAPI
    var id: String { rawValue }

    var label: String {
        switch self {
        case .claudeCLI: "Claude subscription"
        case .codexCLI: "ChatGPT subscription"
        case .anthropicAPI: "Anthropic API key"
        }
    }

    var detail: String {
        switch self {
        case .claudeCLI: "Uses the claude CLI and your Claude plan."
        case .codexCLI: "Uses the codex CLI and your ChatGPT plan."
        case .anthropicAPI: "Pay per request with your own key."
        }
    }

    /// Model choices shown in the prompt bar. The first one is the cheap default.
    var models: [(id: String, label: String)] {
        switch self {
        case .claudeCLI: [("haiku", "Haiku"), ("sonnet", "Sonnet"), ("opus", "Opus")]
        case .codexCLI: [("", "default")] + Self.codexModels.map { ($0, $0) }
        case .anthropicAPI: APIModel.allCases.map { ($0.rawValue, $0.label) }
        }
    }

    /// A short name for the log and the picker, such as "Claude Haiku" or "Codex".
    func displayName(model: String) -> String {
        let label = models.first { $0.id == model }?.label ?? model
        switch self {
        case .claudeCLI: return "Claude \(label)"
        case .codexCLI: return model.isEmpty ? "Codex" : "Codex \(label)"
        case .anthropicAPI: return "\(label) (API)"
        }
    }

    /// The models this Codex install knows about, from the cache the codex CLI keeps.
    private static let codexModels: [String] = {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["slug"] as? String ?? $0["id"] as? String }
            .filter { !$0.contains("review") && !$0.contains("reserve") }
    }()
}

enum Backends {
    static func ask(kind: BackendKind, model: String, system: String, user: String) async throws -> BackendReply {
        switch kind {
        case .claudeCLI: try await claude(model: model, system: system, user: user)
        case .codexCLI: try await codex(model: model, system: system, user: user)
        case .anthropicAPI: try await api(model: APIModel(rawValue: model) ?? .haiku, system: system, user: user)
        }
    }

    private static func claude(model: String, system: String, user: String) async throws -> BackendReply {
        var args = ["-p", user, "--model", model, "--system-prompt", system, "--tools", "",
                    "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
                    "--output-format", "json", "--json-schema", EditPlan.jsonSchema]
        if model != "haiku" { args += ["--effort", "low"] }
        let result = try await CLI.run("claude", args)
        if result.stdout.isEmpty { throw BackendError.message(result.stderrSummary ?? "claude printed nothing.") }
        return try BackendOutput.claudeCLI(result.stdout)
    }

    private static func codex(model: String, system: String, user: String) async throws -> BackendReply {
        let dir = try CLI.scratchDirectory()
        let schema = dir.appendingPathComponent("plan-schema.json")
        let last = dir.appendingPathComponent("last-\(UUID().uuidString).txt")
        try Data(EditPlan.jsonSchema.utf8).write(to: schema)
        defer { try? FileManager.default.removeItem(at: last) }
        var args = ["exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
                    "-C", dir.path, "-c", "model_reasoning_effort=low",
                    "--output-schema", schema.path, "-o", last.path, "--json"]
        if !model.isEmpty { args += ["-m", model] }
        args.append("\(system)\n\n\(user)")
        let result = try await CLI.run("codex", args)
        let message = (try? String(contentsOf: last, encoding: .utf8)) ?? ""
        do {
            return try BackendOutput.codex(lastMessage: message, events: String(decoding: result.stdout, as: UTF8.self))
        } catch BackendError.message(let text) where message.isEmpty && result.stderrSummary != nil {
            throw BackendError.message("\(text) \(result.stderrSummary ?? "")")
        }
    }

    private static func api(model: APIModel, system: String, user: String) async throws -> BackendReply {
        guard let key = Keychain.apiKey, !key.isEmpty else {
            throw BackendError.message("Add your Anthropic API key in Settings.")
        }
        let schema = try JSONSerialization.jsonObject(with: Data(EditPlan.jsonSchema.utf8))
        var output: [String: Any] = ["format": ["type": "json_schema", "schema": schema]]
        if model != .haiku { output["effort"] = "low" }
        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 8000,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": user]],
            "output_config": output,
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try BackendOutput.anthropicAPI(data, model: model)
    }
}
