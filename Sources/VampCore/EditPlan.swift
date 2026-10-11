import Foundation

/// The agent's answer: a short summary plus the smallest set of edits to the song.
/// Every backend (Claude CLI, Codex CLI, Anthropic API) returns this same shape.
public struct EditPlan: Codable, Equatable, Sendable {
    /// The model's production plan, written before the edits. Optional, so older replies decode.
    public var plan: String?
    public var summary: String
    public var edits: [Edit]

    public enum Op: String, Codable, Sendable {
        case addLayer = "add_layer", updateLayer = "update_layer", removeLayer = "remove_layer"
        case setTempo = "set_tempo", setTitle = "set_title"
        case addSection = "add_section", updateSection = "update_section", removeSection = "remove_section"
    }

    public struct Edit: Codable, Equatable, Sendable {
        public var op: Op
        public var layerID: String?
        public var sectionID: String?
        public var name: String?
        public var role: LayerRole?
        public var code: String?
        public var gain: Double?
        public var bpm: Double?
        public var title: String?
        public var bars: Int?
        public var layers: [String]?
        public var position: Int?

        enum CodingKeys: String, CodingKey {
            case op, layerID = "layer_id", sectionID = "section_id", name, role, code, gain, bpm, title, bars, layers, position
        }

        public init(op: Op, layerID: String? = nil, sectionID: String? = nil, name: String? = nil, role: LayerRole? = nil,
                    code: String? = nil, gain: Double? = nil, bpm: Double? = nil, title: String? = nil,
                    bars: Int? = nil, layers: [String]? = nil, position: Int? = nil) {
            self.op = op
            self.layerID = layerID
            self.sectionID = sectionID
            self.name = name
            self.role = role
            self.code = code
            self.gain = gain
            self.bpm = bpm
            self.title = title
            self.bars = bars
            self.layers = layers
            self.position = position
        }

        /// Applies the edit and reports which layer or section it touched.
        /// - Parameter existingLayers: the layers the song had before the whole plan. A first section
        ///   wraps only these as "Main"; nil wraps every current layer.
        @discardableResult
        public func apply(to song: inout Song, existingLayers: [String]? = nil) throws -> Change {
            switch op {
            case .addLayer:
                guard let code = nonEmpty(code) else { throw EditError.missing("code", op) }
                let target = try sectionID.map { try existingSection(in: song, id: $0) }
                let name = nonEmpty(self.name) ?? "Layer"
                let id = song.uniqueID(for: name)
                song.layers.append(Layer(id: id, name: name, role: role ?? .lead, code: code,
                                         gain: clampGain(gain ?? 0.8)))
                // A layer for one section plays only there; otherwise it joins every section.
                for i in song.sections.indices where target == nil || target == i {
                    song.sections[i].layerIDs.append(id)
                }
                return .added(id)
            case .updateLayer:
                let index = try existing(in: song)
                if let name = nonEmpty(name) { song.layers[index].name = name }
                if let role { song.layers[index].role = role }
                if let gain { song.layers[index].gain = clampGain(gain) }
                if let code = nonEmpty(code) {
                    if let sectionID {
                        song.sections[try existingSection(in: song, id: sectionID)].variations[song.layers[index].id] = Layer.cleaned(code)
                    } else {
                        song.layers[index].code = Layer.cleaned(code)
                    }
                }
                return .changed(song.layers[index].id)
            case .removeLayer:
                let id = song.layers[try existing(in: song)].id
                song.removeLayer(id)
                return .removed(id)
            case .addSection:
                return .sectionAdded(song.addSection(name: nonEmpty(name) ?? "Section", bars: bars,
                                                     layerIDs: layers, position: position, wrapping: existingLayers))
            case .updateSection:
                let index = try existingSection(in: song, id: sectionID)
                if let name = nonEmpty(name) { song.sections[index].name = name }
                if let bars { song.sections[index].bars = min(max(bars, Section.barRange.lowerBound), Section.barRange.upperBound) }
                if let layers { song.sections[index].layerIDs = song.knownLayers(layers) }
                let id = song.sections[index].id
                if let position { song.moveSection(at: index, to: position) }
                return .sectionChanged(id)
            case .removeSection:
                let index = try existingSection(in: song, id: sectionID)
                return .sectionRemoved(song.sections.remove(at: index).id)
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

        private func existingSection(in song: Song, id: String?) throws -> Int {
            guard let id, let index = song.sections.firstIndex(where: { $0.id == id }) else {
                throw EditError.unknownSection(id ?? "nil")
            }
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
        case sectionAdded(String), sectionChanged(String), sectionRemoved(String)
    }
}

public enum EditError: Error, Equatable, LocalizedError {
    case missing(String, EditPlan.Op)
    case unknownLayer(String)
    case unknownSection(String)

    public var errorDescription: String? {
        switch self {
        case let .missing(field, op): "\(op.rawValue) needs a \(field)."
        case let .unknownLayer(id): "No layer has the id \"\(id)\"."
        case let .unknownSection(id): "No section has the id \"\(id)\"."
        }
    }
}

public extension EditPlan {
    /// Strict JSON Schema for the plan. Every field is required and nullable, which
    /// both Claude structured output and the Codex output schema accept.
    static let jsonSchema = """
    {"type":"object","additionalProperties":false,"required":["plan","summary","edits"],"properties":{\
    "plan":{"type":"string","description":"Written before the edits. For a whole song: genre, key, tempo, \
    form with bars and length, chord progression per section, energy per section, palette, register map. \
    For a small change: one sentence."},\
    "summary":{"type":"string","description":"One short sentence for the musician about what changed."},\
    "edits":{"type":"array","items":{"type":"object","additionalProperties":false,\
    "required":["op","layer_id","section_id","name","role","code","gain","bpm","title","bars","layers","position"],"properties":{\
    "op":{"type":"string","enum":["add_layer","update_layer","remove_layer","set_tempo","set_title",\
    "add_section","update_section","remove_section"]},\
    "layer_id":{"type":["string","null"],"description":"Existing layer id for update_layer and remove_layer."},\
    "section_id":{"type":["string","null"],"description":"Existing section id. With add_layer or update_layer, limits the change to that section."},\
    "name":{"type":["string","null"]},\
    "role":{"type":["string","null"],"enum":["drums","percussion","bass","chords","pad","lead","arp","fx",null]},\
    "code":{"type":["string","null"],"description":"Full Strudel expression for the layer. Null keeps the current code."},\
    "gain":{"type":["number","null"],"description":"Layer volume from 0 to 1.5."},\
    "bpm":{"type":["number","null"]},\
    "title":{"type":["string","null"]},\
    "bars":{"type":["integer","null"],"description":"Section length in bars, 1 to 64."},\
    "layers":{"type":["array","null"],"items":{"type":"string"},"description":"Layer ids that play in the section."},\
    "position":{"type":["integer","null"],"description":"Section index after the edit. 0 is the start of the song."}}}}}}
    """
}
