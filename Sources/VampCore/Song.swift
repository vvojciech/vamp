import Foundation

/// What a layer does in the arrangement. It sets the lane colour and guides the agent.
public enum LayerRole: String, Codable, CaseIterable, Sendable {
    case drums, percussion, bass, chords, pad, lead, arp, fx
}

/// One line of the song: a single Strudel pattern expression with its own mix settings.
public struct Layer: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var role: LayerRole
    public var code: String
    public var gain: Double
    public var muted: Bool
    public var solo: Bool

    public init(id: String, name: String, role: LayerRole, code: String, gain: Double = 0.8, muted: Bool = false, solo: Bool = false) {
        self.id = id
        self.name = name
        self.role = role
        self.code = Layer.cleaned(code)
        self.gain = gain
        self.muted = muted
        self.solo = solo
    }

    /// Removes blank edges and trailing semicolons, which break the wrapping in `stack(...)`.
    public static func cleaned(_ code: String) -> String {
        var text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        return text
    }
}

/// The music sheet: tempo plus the layers that play together.
public struct Song: Codable, Equatable, Sendable {
    public var title: String
    public var bpm: Double
    public var layers: [Layer]

    public init(title: String, bpm: Double, layers: [Layer]) {
        self.title = title
        self.bpm = bpm
        self.layers = layers
    }

    public static let bpmRange: ClosedRange<Double> = 40...220
    public static let gainRange: ClosedRange<Double> = 0...1.5

    /// Solo layers win. Otherwise every layer that is not muted plays.
    public var audibleLayers: [Layer] {
        let soloed = layers.filter(\.solo)
        return soloed.isEmpty ? layers.filter { !$0.muted } : soloed
    }

    /// The full Strudel program. One cycle is one bar of four beats.
    /// - Parameter codeOverrides: code to use in place of a layer's own code, for example its last valid version.
    public func composedCode(codeOverrides: [String: String] = [:]) -> String? {
        let parts = audibleLayers.map { layer in
            let code = codeOverrides[layer.id] ?? layer.code
            return "  (\n\(code)\n  ).postgain(\(String(format: "%.2f", layer.gain)))"
        }
        guard !parts.isEmpty else { return nil }
        return "setcps(\(Int(bpm.rounded()))/60/4)\nstack(\n\(parts.joined(separator: ",\n"))\n)"
    }

    public func index(of id: String) -> Int? { layers.firstIndex { $0.id == id } }

    /// A readable slug that no other layer uses.
    public func uniqueID(for name: String) -> String {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        let base = slug.isEmpty ? "layer" : slug
        var candidate = base
        var n = 2
        while index(of: candidate) != nil {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }
}

public extension Song {
    static let starter = Song(title: "Night Drive", bpm: 112, layers: [
        Layer(id: "drums", name: "Drums", role: .drums,
              code: "s(\"bd*4, [~ cp]*2, [~ hh]*4\").gain(0.9)", gain: 0.85),
        Layer(id: "bass", name: "Bass", role: .bass,
              code: "note(\"<c2 c2 ab1 bb1>*8\")\n  .s(\"sawtooth\").lpf(sine.range(300, 1400).slow(8)).lpq(6)\n  .decay(0.18).sustain(0)", gain: 0.7),
        Layer(id: "chords", name: "Chords", role: .chords,
              code: "chord(\"<Cm9 Ab^7 Fm9 Bb7>\").voicing()\n  .s(\"supersaw\").lpf(1600).attack(0.08).release(0.8)\n  .room(0.5).gain(0.3)", gain: 0.6),
        Layer(id: "arp", name: "Arp", role: .arp,
              code: "n(\"0 2 4 [7 9] 4 2 [0 -3] ~\").scale(\"<C4:minor Ab3:major F3:minor Bb3:mixolydian>\")\n  .s(\"triangle\").decay(0.2).sustain(0)\n  .delay(0.35).delaytime(0.1875).room(0.3)", gain: 0.5),
    ])
}
