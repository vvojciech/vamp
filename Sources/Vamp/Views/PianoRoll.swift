import SwiftUI
import VampCore

/// Where each event sits in a lane: pitch rows for melodic layers, one row per sound for drums.
struct LaneLayout {
    enum Kind { case pitched(low: Double, high: Double), drums(rows: [String]) }
    let kind: Kind

    init(events: [NoteEvent]) {
        let pitches = events.compactMap(\.midi)
        if pitches.count * 2 >= events.count, let low = pitches.min(), let high = pitches.max() {
            let pad = max(2, (12 - (high - low)) / 2)
            kind = .pitched(low: low - pad, high: high + pad)
        } else {
            let names = Set(events.compactMap { $0.sound?.split(separator: ":").first.map(String.init) })
            kind = .drums(rows: names.sorted { LaneLayout.drumOrder($0) < LaneLayout.drumOrder($1) })
        }
    }

    /// Kicks at the bottom, cymbals at the top, like a drum chart.
    static func drumOrder(_ name: String) -> String {
        let order = ["cr", "oh", "ho", "808oh", "hh", "hh27", "808hc", "rm", "cb", "perc", "ht", "mt", "lt", "cp", "sd", "sn", "808sd", "bd", "808bd"]
        let rank = order.firstIndex { name == $0 } ?? order.firstIndex { name.hasSuffix($0) } ?? -1
        return String(format: "%03d-%@", rank < 0 ? 50 : rank, name)
    }

    /// Vertical centre and height for one event, in a lane of the given height.
    func row(for event: NoteEvent, height: CGFloat) -> (y: CGFloat, h: CGFloat) {
        switch kind {
        case let .pitched(low, high):
            let span = max(high - low, 1)
            let step = height / CGFloat(span)
            let midi = event.midi ?? low
            return (height - CGFloat(midi - low) * step, min(max(step * 0.9, 4), 9))
        case let .drums(rows):
            let name = event.sound?.split(separator: ":").first.map(String.init) ?? ""
            let count = max(rows.count, 1)
            let index = rows.firstIndex(of: name) ?? 0
            let step = height / CGFloat(count)
            return (height - (CGFloat(index) + 0.5) * step, min(max(step * 0.62, 4), 12))
        }
    }

    var rowLabels: [String] {
        if case let .drums(rows) = kind { return rows }
        return []
    }
}

/// Draws one layer's events for `bars` bars, with notes under the playhead lit up.
struct PianoRoll: View {
    let events: [NoteEvent]
    let bars: Int
    let tint: Color
    let dimmed: Bool
    let position: Double?

    var body: some View {
        Canvas { context, size in
            let layout = LaneLayout(events: events)
            let inset: CGFloat = 8
            let height = size.height - inset * 2
            let barWidth = size.width / CGFloat(bars)

            for beat in 0..<(bars * 4) where beat > 0 {
                let x = CGFloat(beat) * barWidth / 4
                let path = Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }
                context.stroke(path, with: .color(beat % 4 == 0 ? Theme.lineStrong : Theme.line), lineWidth: 1)
            }

            let now = position.map { $0.truncatingRemainder(dividingBy: Double(bars)) }
            for event in events where event.begin < Double(bars) {
                let (y, h) = layout.row(for: event, height: height)
                let x = CGFloat(event.begin) * barWidth
                let w = max(CGFloat(min(event.end, Double(bars)) - event.begin) * barWidth - 1.5, 3)
                let rect = CGRect(x: x + 0.75, y: inset + y - h / 2, width: w, height: h)
                let active = now.map { event.begin <= $0 && $0 < event.end } ?? false
                let alpha = (dimmed ? 0.28 : 0.55 + 0.45 * min(event.gain, 1)) * (active ? 1 : 0.82)
                let shape = Path(roundedRect: rect, cornerRadius: min(h / 2, 3.5))
                if active && !dimmed {
                    var glow = context
                    glow.addFilter(.shadow(color: tint.opacity(0.9), radius: 6))
                    glow.fill(shape, with: .color(.white.opacity(0.95)))
                } else {
                    context.fill(shape, with: .color(tint.opacity(alpha)))
                }
            }

            for label in layout.rowLabels {
                let (y, _) = layout.row(for: NoteEvent(begin: 0, end: 0, midi: nil, sound: label, gain: 1), height: height)
                let text = Text(label).font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.muted)
                let resolved = context.resolve(text)
                let textSize = resolved.measure(in: size)
                let pill = CGRect(x: 3, y: inset + y - textSize.height / 2 - 1.5, width: textSize.width + 8, height: textSize.height + 3)
                context.fill(Path(roundedRect: pill, cornerRadius: 3), with: .color(Theme.lane))
                context.draw(resolved, at: CGPoint(x: 7, y: inset + y), anchor: .leading)
            }
        }
    }
}
