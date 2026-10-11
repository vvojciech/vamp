import Foundation

/// Key detection and scale checks on note events.
public enum MusicTheory {
    public struct Key: Equatable, Sendable {
        public var tonic: Int
        public var minor: Bool

        public init(tonic: Int, minor: Bool) {
            self.tonic = tonic
            self.minor = minor
        }

        public var name: String { "\(MusicTheory.pitchNames[tonic]) \(minor ? "minor" : "major")" }

        /// Pitch classes that sound in key. Minor allows the raised 6th and 7th (melodic and harmonic minor).
        public var pitchClasses: Set<Int> {
            let steps = minor ? [0, 2, 3, 5, 7, 8, 9, 10, 11] : [0, 2, 4, 5, 7, 9, 11]
            return Set(steps.map { ($0 + tonic) % 12 })
        }
    }

    public static let pitchNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    // Krumhansl-Kessler key profiles.
    private static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    public static func pitchClass(_ midi: Double) -> Int { ((Int(midi.rounded()) % 12) + 12) % 12 }

    /// Time spent on each pitch class.
    public static func histogram(_ events: [NoteEvent]) -> [Double] {
        var weights = Array(repeating: 0.0, count: 12)
        for event in events { if let midi = event.midi { weights[pitchClass(midi)] += max(event.end - event.begin, 0.01) } }
        return weights
    }

    /// The best-fitting key by correlation with the key profiles.
    public static func key(of events: [NoteEvent]) -> Key {
        let weights = histogram(events)
        var best = (key: Key(tonic: 0, minor: false), r: -Double.infinity)
        for tonic in 0..<12 {
            for minor in [false, true] {
                let profile = minor ? minorProfile : majorProfile
                let rotated = (0..<12).map { profile[($0 - tonic + 12) % 12] }
                let r = correlation(weights, rotated)
                if r > best.r { best = (Key(tonic: tonic, minor: minor), r) }
            }
        }
        return best.key
    }

    /// Share of note time spent in the key.
    public static func inKeyRatio(_ events: [NoteEvent], key: Key) -> Double {
        let weights = histogram(events)
        let total = weights.reduce(0, +)
        guard total > 0 else { return 1 }
        return key.pitchClasses.map { weights[$0] }.reduce(0, +) / total
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let meanA = a.reduce(0, +) / Double(a.count), meanB = b.reduce(0, +) / Double(b.count)
        var num = 0.0, denA = 0.0, denB = 0.0
        for i in a.indices {
            num += (a[i] - meanA) * (b[i] - meanB)
            denA += (a[i] - meanA) * (a[i] - meanA)
            denB += (b[i] - meanB) * (b[i] - meanB)
        }
        return denA == 0 || denB == 0 ? 0 : num / (denA * denB).squareRoot()
    }
}
