import Foundation
import VampCore

/// Moving around the song: the play cursor, section jumps and the playing position.
extension AppModel {
    /// True when the song plays once from a cursor; loops and looped sections have no cursor.
    var canSeek: Bool { !song.sections.isEmpty && !loopsSection }

    /// The playing position in song bars, or nil when stopped.
    func songPosition(at date: Date) -> Double? {
        engine.position(at: date, bpm: song.bpm).map { $0 + Double(playStartBar) }
    }

    /// Moves the cursor. If the song is playing, playback jumps there.
    func seek(toBar bar: Int) {
        guard canSeek else { return }
        cursorBar = max(0, min(bar, (song.totalBars ?? 1) - 1))
        if engine.isPlaying { start() }
    }

    func play(fromSection id: String) {
        guard let bar = song.startBar(ofSection: id) else { return }
        if loopsSection { loopsSection = false }
        cursorBar = bar
        selectedSectionID = id
        start()
    }

    /// The bar the transport acts on: the playhead while playing, otherwise the cursor.
    private var currentBar: Double { songPosition(at: Date()) ?? Double(cursorBar) }

    func nextSection() {
        guard canSeek, let bar = song.nextSectionStart(after: currentBar) else { return }
        seek(toBar: bar)
    }

    func previousSection() {
        guard canSeek else { return }
        seek(toBar: song.previousSectionStart(before: currentBar))
    }
}
