import Foundation

/// One finished exchange, kept short so each new prompt stays cheap.
public struct Turn: Codable, Equatable, Sendable {
    public var request: String
    public var summary: String
    public init(request: String, summary: String) {
        self.request = request
        self.summary = summary
    }
}

public enum AgentPrompt {

    /// The per-request message: the current sheet, recent turns, then the request.
    public static func user(request: String, song: Song, history: [Turn]) -> String {
        var text = "CURRENT SONG\n\(songJSON(song))\n"
        if !history.isEmpty {
            let recent = history.suffix(4).map { "- Musician: \($0.request)\n  You: \($0.summary)" }
            text += "\nEARLIER IN THIS SESSION\n\(recent.joined(separator: "\n"))\n"
        }
        return text + "\nREQUEST\n\(request)"
    }

    /// Asks for a corrected plan after the engine rejected some layer code.
    public static func repair(original: String, plan: EditPlan, errors: [String: String]) -> String {
        let list = errors.sorted { $0.key < $1.key }.map { "- layer \($0.key): \($0.value)" }.joined(separator: "\n")
        let planText = (try? String(decoding: encoder.encode(plan), as: UTF8.self)) ?? ""
        return "\(original)\n\nYOUR LAST PLAN\n\(planText)\n\nSTRUDEL REJECTED IT\n\(list)\n\nReturn a corrected plan for the same request."
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func songJSON(_ song: Song) -> String {
        String(decoding: (try? encoder.encode(song)) ?? Data(), as: UTF8.self)
    }
}
