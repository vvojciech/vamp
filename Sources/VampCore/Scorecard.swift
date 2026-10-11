import Foundation

/// What the critic rates. Each aspect gets a score from 0 to 10 and notes on what to fix.
public enum AspectName: String, Codable, CaseIterable, Sendable {
    case form, energy, harmony, groove, melody, sound, mix

    public var label: String {
        switch self {
        case .form: "Form"
        case .energy: "Energy arc"
        case .harmony: "Harmony"
        case .groove: "Groove"
        case .melody: "Melody"
        case .sound: "Sound design"
        case .mix: "Mix"
        }
    }
}

public struct Aspect: Codable, Equatable, Sendable {
    public var name: AspectName
    public var score: Double
    public var notes: [String]

    public init(name: AspectName, score: Double, notes: [String]) {
        self.name = name
        self.score = score
        self.notes = notes
    }
}

public struct Scorecard: Codable, Equatable, Sendable {
    public var aspects: [Aspect]

    public init(aspects: [Aspect]) { self.aspects = aspects }

    /// The song is only as good as its weakest aspect.
    public var overall: Double { aspects.map(\.score).min() ?? 0 }

    public func score(_ name: AspectName) -> Double { aspects.first { $0.name == name }?.score ?? 0 }
    public func notes(_ name: AspectName) -> [String] { aspects.first { $0.name == name }?.notes ?? [] }

    /// Keeps the lower score per aspect and the notes of both, for example measured and judged.
    public func combined(with other: Scorecard) -> Scorecard {
        Scorecard(aspects: AspectName.allCases.compactMap { name in
            let mine = aspects.first { $0.name == name }, theirs = other.aspects.first { $0.name == name }
            guard mine != nil || theirs != nil else { return nil }
            let score = min(mine?.score ?? 10, theirs?.score ?? 10)
            return Aspect(name: name, score: score, notes: (mine?.notes ?? []) + (theirs?.notes ?? []))
        })
    }

    /// Plain text for an agent prompt, weakest aspect first.
    public var report: String {
        aspects.sorted { $0.score < $1.score }.map { aspect in
            let notes = aspect.notes.isEmpty ? "" : "\n" + aspect.notes.map { "  - \($0)" }.joined(separator: "\n")
            return "\(aspect.name.label): \(String(format: "%.1f", aspect.score))/10\(notes)"
        }.joined(separator: "\n")
    }
}

/// A score that starts at 10 and loses points for each problem found.
public struct Measured: Equatable, Sendable {
    public private(set) var score: Double = 10
    public private(set) var notes: [String] = []

    public init(score: Double = 10) { self.score = score }

    mutating func penalise(_ points: Double, _ note: String) {
        score = max(0, score - points)
        notes.append(note)
    }

    func aspect(_ name: AspectName) -> Aspect { Aspect(name: name, score: score, notes: notes) }
}
