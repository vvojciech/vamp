import Foundation

/// A named part of the song, such as Intro or Bridge. It lasts `bars` bars and plays the
/// layers in `layerIDs`. A layer can have different code in one section through `variations`.
public struct Section: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var bars: Int
    public var layerIDs: [String]
    public var variations: [String: String]

    public static let barRange: ClosedRange<Int> = 1...64

    public init(id: String, name: String, bars: Int, layerIDs: [String], variations: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.bars = min(max(bars, Section.barRange.lowerBound), Section.barRange.upperBound)
        self.layerIDs = layerIDs
        self.variations = variations
    }
}

public extension Song {
    /// Length of the whole arrangement, or nil when the song is one loop.
    var totalBars: Int? { sections.isEmpty ? nil : sections.map(\.bars).reduce(0, +) }

    /// Playing time of the arrangement. One bar is 4 beats: bars × 240 ÷ BPM.
    var durationSeconds: Double? { totalBars.map { Double($0) * 240 / bpm } }

    /// The cycle where playback stops, or nil when it should loop.
    func playbackEnd(tailBars: Int, loopingSection: String?) -> Double? {
        guard loopingSection == nil, let total = totalBars else { return nil }
        return Double(total + tailBars)
    }

    /// "3:12".
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    func section(_ id: String) -> Section? { sections.first { $0.id == id } }

    /// The code a layer plays in one section, or nil when it rests there.
    func code(for layer: Layer, in section: Section) -> String? {
        guard section.layerIDs.contains(layer.id) else { return nil }
        return section.variations[layer.id].map(Layer.cleaned) ?? layer.code
    }

    /// The layer's full Strudel program. With sections, it is an `arrange(...)` with silence
    /// where the layer rests. Nil means the layer plays in no section.
    func program(for layer: Layer) -> String? {
        guard !sections.isEmpty else { return layer.code }
        guard sections.contains(where: { $0.layerIDs.contains(layer.id) }) else { return nil }
        let rows = sections.map { section in
            code(for: layer, in: section).map { "  [\(section.bars), (\n\($0)\n  )]" } ?? "  [\(section.bars), silence]"
        }
        return "arrange(\n\(rows.joined(separator: ",\n"))\n)"
    }

    /// Removes a layer and every reference to it.
    mutating func removeLayer(_ id: String) {
        layers.removeAll { $0.id == id }
        for i in sections.indices {
            sections[i].layerIDs.removeAll { $0 == id }
            sections[i].variations[id] = nil
        }
    }

    func uniqueSectionID(for name: String) -> String {
        let probe = Song(title: "", bpm: bpm, layers: sections.map { Layer(id: $0.id, name: $0.name, role: .fx, code: "") })
        return probe.uniqueID(for: name)
    }

    /// Adds a section. The first one wraps the current loop as "Main", so nothing that plays now is lost.
    @discardableResult
    mutating func addSection(name: String, bars: Int?, layerIDs: [String]?, position: Int?) -> String {
        if sections.isEmpty {
            sections = [Section(id: "main", name: "Main", bars: 8, layerIDs: layers.map(\.id))]
        }
        let id = uniqueSectionID(for: name)
        let section = Section(id: id, name: name, bars: bars ?? 8, layerIDs: knownLayers(layerIDs ?? layers.map(\.id)))
        sections.insert(section, at: clampedPosition(position, count: sections.count))
        return id
    }

    mutating func moveSection(at index: Int, to position: Int) {
        let section = sections.remove(at: index)
        sections.insert(section, at: clampedPosition(position, count: sections.count))
    }

    /// Keeps only ids of layers that exist, in song order.
    func knownLayers(_ ids: [String]) -> [String] {
        layers.map(\.id).filter(ids.contains)
    }

    private func clampedPosition(_ position: Int?, count: Int) -> Int {
        min(max(position ?? count, 0), count)
    }
}
