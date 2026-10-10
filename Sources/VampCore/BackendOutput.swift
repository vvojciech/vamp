import Foundation

/// The raw plan JSON from any backend, plus what it cost.
public struct BackendReply: Sendable {
    public var json: Data
    public var costUSD: Double?
    public var inputTokens: Int
    public var outputTokens: Int

    public init(json: Data, costUSD: Double?, inputTokens: Int, outputTokens: Int) {
        self.json = json
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum BackendError: Error, Equatable, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}

/// Models offered for the Anthropic API backend, with list prices per million tokens.
public enum APIModel: String, CaseIterable, Codable, Sendable {
    case haiku = "claude-haiku-4-5", sonnet = "claude-sonnet-5", opus = "claude-opus-5"

    public var label: String {
        switch self {
        case .haiku: "Haiku 4.5"
        case .sonnet: "Sonnet 5"
        case .opus: "Opus 5"
        }
    }

    var price: (input: Double, output: Double) {
        switch self {
        case .haiku: (1, 5)
        case .sonnet: (2, 10)
        case .opus: (5, 25)
        }
    }

    public func cost(input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0) -> Double {
        let perToken = price.input / 1_000_000
        return Double(input) * perToken + Double(cacheRead) * perToken * 0.1
            + Double(cacheWrite) * perToken * 1.25 + Double(output) * price.output / 1_000_000
    }
}

/// Parsers for what each backend prints. Pure functions, so they are unit tested.
public enum BackendOutput {
    /// `claude -p --output-format json --json-schema ...`
    public static func claudeCLI(_ data: Data) throws -> BackendReply {
        let root = try object(data)
        if root["is_error"] as? Bool == true {
            throw BackendError.message(root["result"] as? String ?? "Claude returned an error.")
        }
        guard let structured = root["structured_output"] else {
            throw BackendError.message("Claude did not return a plan.")
        }
        let usage = root["usage"] as? [String: Any] ?? [:]
        return BackendReply(json: try JSONSerialization.data(withJSONObject: structured),
                            costUSD: root["total_cost_usd"] as? Double,
                            inputTokens: usage["input_tokens"] as? Int ?? 0,
                            outputTokens: usage["output_tokens"] as? Int ?? 0)
    }

    /// `codex exec --json --output-schema ... -o <file>`: the last message file plus the JSONL events.
    public static func codex(lastMessage: String, events: String) throws -> BackendReply {
        var usage: [String: Any] = [:]
        for line in events.split(separator: "\n") {
            guard let event = try? object(Data(line.utf8)) else { continue }
            switch event["type"] as? String {
            case "turn.completed": usage = event["usage"] as? [String: Any] ?? [:]
            case "turn.failed", "error":
                let error = event["error"] as? [String: Any]
                throw BackendError.message(error?["message"] as? String ?? event["message"] as? String ?? "Codex failed.")
            default: break
            }
        }
        let text = lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BackendError.message("Codex did not return a plan.") }
        return BackendReply(json: Data(text.utf8), costUSD: nil,
                            inputTokens: usage["input_tokens"] as? Int ?? 0,
                            outputTokens: usage["output_tokens"] as? Int ?? 0)
    }

    /// `POST /v1/messages` with `output_config.format` set to the plan schema.
    public static func anthropicAPI(_ data: Data, model: APIModel) throws -> BackendReply {
        let root = try object(data)
        if let error = root["error"] as? [String: Any] {
            throw BackendError.message(error["message"] as? String ?? "The API returned an error.")
        }
        if root["stop_reason"] as? String == "refusal" { throw BackendError.message("The model declined this request.") }
        if root["stop_reason"] as? String == "max_tokens" { throw BackendError.message("The reply was cut off. Try a smaller change.") }
        let blocks = root["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        let usage = root["usage"] as? [String: Any] ?? [:]
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cost = model.cost(input: input, output: output,
                              cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                              cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
        return BackendReply(json: Data(text.utf8), costUSD: cost, inputTokens: input, outputTokens: output)
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let preview = String(decoding: data.prefix(300), as: UTF8.self)
            throw BackendError.message(preview.isEmpty ? "The backend printed nothing." : preview)
        }
        return root
    }
}
