import Foundation

/// One note or hit, as Strudel produced it. Times are in cycles (bars) from the song start.
public struct NoteEvent: Codable, Hashable, Sendable {
    public var begin: Double
    public var end: Double
    /// Pitch as a MIDI number, or nil for an unpitched hit.
    public var midi: Double?
    /// Sample or synth name, such as "bd" or "sawtooth".
    public var sound: String?
    /// Drum-machine bank, such as "RolandTR909".
    public var bank: String?
    public var gain: Double

    public init(begin: Double, end: Double, midi: Double? = nil, sound: String? = nil, bank: String? = nil, gain: Double = 1) {
        self.begin = begin
        self.end = end
        self.midi = midi
        self.sound = sound
        self.bank = bank
        self.gain = gain
    }
}
