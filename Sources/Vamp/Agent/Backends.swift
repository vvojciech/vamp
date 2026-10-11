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

    /// The model that writes whole songs. Quality matters more than speed here.
    var composerModel: String {
        switch self {
        case .claudeCLI: "opus"
        case .codexCLI: ""
        case .anthropicAPI: APIModel.opus.rawValue
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

/// One call to a model: the prompts, the JSON schema of the answer, and how hard to think.
struct BackendRequest {
    var kind: BackendKind
    var model: String
    var system: String
    var user: String
    var schema: String = EditPlan.jsonSchema
    /// "low" for quick edits; "high" for composing and judging whole songs.
    var effort = "low"
    var timeout: TimeInterval = 180
}

enum Backends {
    static func ask(_ request: BackendRequest) async throws -> BackendReply {
        switch request.kind {
        case .claudeCLI: try await claude(request)
        case .codexCLI: try await codex(request)
        case .anthropicAPI: try await api(request, model: APIModel(rawValue: request.model) ?? .haiku)
        }
    }

    private static func claude(_ r: BackendRequest) async throws -> BackendReply {
        var args = ["-p", r.user, "--model", r.model, "--system-prompt", r.system, "--tools", "",
                    "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
                    "--output-format", "json", "--json-schema", r.schema]
        if r.model != "haiku" { args += ["--effort", r.effort] }
        let result = try await CLI.run("claude", args, timeout: r.timeout)
        if result.stdout.isEmpty { throw BackendError.message(result.stderrSummary ?? "claude printed nothing.") }
        return try BackendOutput.claudeCLI(result.stdout)
    }

    private static func codex(_ r: BackendRequest) async throws -> BackendReply {
        let dir = try CLI.scratchDirectory()
        let id = UUID().uuidString
        let schema = dir.appendingPathComponent("schema-\(id).json")
        let last = dir.appendingPathComponent("last-\(id).txt")
        try Data(r.schema.utf8).write(to: schema)
        defer {
            try? FileManager.default.removeItem(at: last)
            try? FileManager.default.removeItem(at: schema)
        }
        var args = ["exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
                    "-C", dir.path, "-c", "model_reasoning_effort=\(r.effort)",
                    "--output-schema", schema.path, "-o", last.path, "--json"]
        if !r.model.isEmpty { args += ["-m", r.model] }
        args.append("\(r.system)\n\n\(r.user)")
        let result = try await CLI.run("codex", args, timeout: r.timeout)
        let message = (try? String(contentsOf: last, encoding: .utf8)) ?? ""
        do {
            return try BackendOutput.codex(lastMessage: message, events: String(decoding: result.stdout, as: UTF8.self))
        } catch BackendError.message(let text) where message.isEmpty && result.stderrSummary != nil {
            throw BackendError.message("\(text) \(result.stderrSummary ?? "")")
        }
    }

    private static func api(_ r: BackendRequest, model: APIModel) async throws -> BackendReply {
        guard let key = Keychain.apiKey, !key.isEmpty else {
            throw BackendError.message("Add your Anthropic API key in Settings.")
        }
        let schema = try JSONSerialization.jsonObject(with: Data(r.schema.utf8))
        var output: [String: Any] = ["format": ["type": "json_schema", "schema": schema]]
        if model != .haiku { output["effort"] = r.effort }
        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16000,
            "system": [["type": "text", "text": r.system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": r.user]],
            "output_config": output,
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = r.timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try BackendOutput.anthropicAPI(data, model: model)
    }
}
