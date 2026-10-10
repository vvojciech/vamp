import Foundation

/// The agent's answer: a short summary plus the smallest set of edits to the song.
/// Every backend (Claude CLI, Codex CLI, Anthropic API) returns this same shape.
public struct EditPlan: Codable, Equatable, Sendable {
    public var summary: String
    public var edits: [Edit]

    public enum Op: String, Codable, Sendable {
        case addLayer = "add_layer", updateLayer = "update_layer", removeLayer = "remove_layer"
        case setTempo = "set_tempo", setTitle = "set_title"
    }

    public struct Edit: Codable, Equatable, Sendable {
        public var op: Op
        public var layerID: String?
        public var name: String?
        public var role: LayerRole?
        public var code: String?
        public var gain: Double?
        public var bpm: Double?
        public var title: String?

        enum CodingKeys: String, CodingKey {
            case op, layerID = "layer_id", name, role, code, gain, bpm, title
        }

        public init(op: Op, layerID: String? = nil, name: String? = nil, role: LayerRole? = nil,
                    code: String? = nil, gain: Double? = nil, bpm: Double? = nil, title: String? = nil) {
            self.op = op
            self.layerID = layerID
            self.name = name
            self.role = role
            self.code = code
            self.gain = gain
            self.bpm = bpm
            self.title = title
        }

        /// Applies the edit and reports which layer it touched.
        @discardableResult
        public func apply(to song: inout Song) throws -> Change {
            switch op {
            case .addLayer:
                guard let code = nonEmpty(code) else { throw EditError.missing("code", op) }
                let name = nonEmpty(self.name) ?? "Layer"
                let id = song.uniqueID(for: name)
                song.layers.append(Layer(id: id, name: name, role: role ?? .lead, code: code,
                                         gain: clampGain(gain ?? 0.8)))
                return .added(id)
            case .updateLayer:
                let index = try existing(in: song)
                if let name = nonEmpty(name) { song.layers[index].name = name }
                if let role { song.layers[index].role = role }
                if let code = nonEmpty(code) { song.layers[index].code = Layer.cleaned(code) }
                if let gain { song.layers[index].gain = clampGain(gain) }
                return .changed(song.layers[index].id)
            case .removeLayer:
                let index = try existing(in: song)
                return .removed(song.layers.remove(at: index).id)
            case .setTempo:
                guard let bpm else { throw EditError.missing("bpm", op) }
                song.bpm = min(max(bpm, Song.bpmRange.lowerBound), Song.bpmRange.upperBound)
                return .tempo
            case .setTitle:
                guard let title = nonEmpty(title) else { throw EditError.missing("title", op) }
                song.title = title
                return .title
            }
        }

        private func existing(in song: Song) throws -> Int {
            guard let id = layerID, let index = song.index(of: id) else { throw EditError.unknownLayer(layerID ?? "nil") }
            return index
        }

        private func nonEmpty(_ text: String?) -> String? {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }

        private func clampGain(_ value: Double) -> Double {
            min(max(value, Song.gainRange.lowerBound), Song.gainRange.upperBound)
        }
    }

    /// What one edit did, for the change chips in the agent log.
    public enum Change: Equatable, Sendable, Codable {
        case added(String), changed(String), removed(String), tempo, title
    }
}

public enum EditError: Error, Equatable, LocalizedError {
    case missing(String, EditPlan.Op)
    case unknownLayer(String)

    public var errorDescription: String? {
        switch self {
        case let .missing(field, op): "\(op.rawValue) needs a \(field)."
        case let .unknownLayer(id): "No layer has the id \"\(id)\"."
        }
    }
}

public extension EditPlan {
    /// Strict JSON Schema for the plan. Every field is required and nullable, which
    /// both Claude structured output and the Codex output schema accept.
    static let jsonSchema = """
    {"type":"object","additionalProperties":false,"required":["summary","edits"],"properties":{\
    "summary":{"type":"string","description":"One short sentence for the musician about what changed."},\
    "edits":{"type":"array","items":{"type":"object","additionalProperties":false,\
    "required":["op","layer_id","name","role","code","gain","bpm","title"],"properties":{\
    "op":{"type":"string","enum":["add_layer","update_layer","remove_layer","set_tempo","set_title"]},\
    "layer_id":{"type":["string","null"],"description":"Existing layer id for update_layer and remove_layer."},\
    "name":{"type":["string","null"]},\
    "role":{"type":["string","null"],"enum":["drums","percussion","bass","chords","pad","lead","arp","fx",null]},\
    "code":{"type":["string","null"],"description":"Full Strudel expression for the layer. Null keeps the current code."},\
    "gain":{"type":["number","null"],"description":"Layer volume from 0 to 1.5."},\
    "bpm":{"type":["number","null"]},\
    "title":{"type":["string","null"]}}}}}}
    """
}
