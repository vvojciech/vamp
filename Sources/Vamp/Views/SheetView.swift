import SwiftUI
import VampCore

/// The music sheet: the arrangement, a bar ruler, then one lane per layer, all sharing one playhead.
struct SheetView: View {
    @Environment(AppModel.self) private var app
    static let headerWidth: CGFloat = 214

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                TimelineView(.animation(paused: !app.engine.isPlaying)) { timeline in
                    let window = app.window
                    let position = app.engine.position(at: timeline.date, bpm: app.song.bpm)
                        .map { $0.truncatingRemainder(dividingBy: Double(window.count)) }
                    VStack(spacing: 6) {
                        ArrangementBar(position: position)
                        Ruler(start: window.start, bars: window.count, position: position)
                        ForEach(app.song.layers) { layer in
                            LaneView(layer: layer, position: position).id(layer.id)
                        }
                        if app.song.layers.isEmpty { EmptySheet() }
                        AddLayerMenu()
                            .padding(.leading, Self.headerWidth + 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
            .onChange(of: app.selectedLayerID) { _, id in
                // Bring a new or newly selected layer into view, for example one the agent just added.
                if let id { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id) } }
            }
        }
        .background(Theme.window)
    }
}

private struct Ruler: View {
    let start: Int
    let bars: Int
    let position: Double?

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: SheetView.headerWidth)
            GeometryReader { geo in
                let step = max(1, Int((Double(bars) * 34 / max(geo.size.width, 1)).rounded(.up)))
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: 0, to: bars, by: step)), id: \.self) { bar in
                        Text("\(start + bar + 1)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.faint)
                            .offset(x: geo.size.width / CGFloat(bars) * CGFloat(bar) + 4, y: 3)
                    }
                    if let position {
                        Capsule().fill(Theme.playhead).frame(width: 9, height: 9)
                            .offset(x: geo.size.width * CGFloat(position / Double(bars)) - 4.5, y: 4)
                    }
                }
            }
            .frame(height: 18)
        }
    }
}

private struct LaneView: View {
    @Environment(AppModel.self) private var app
    let layer: Layer
    let position: Double?

    private var isSelected: Bool { app.selectedLayerID == layer.id && !app.inspectsSection }
    private var isAudible: Bool { app.song.audibleLayers.contains { $0.id == layer.id } }

    var body: some View {
        let tint = Theme.color(for: layer.role)
        let result = app.analysis[layer.id]
        let window = app.window
        HStack(spacing: 12) {
            LaneHeader(layer: layer,
                       error: result.flatMap { if case let .failure(e) = $0 { e.message } else { nil } },
                       eventsPerBar: result.flatMap { if case let .success(events) = $0 { eventsPerBar(events) } else { nil } })
                .frame(width: SheetView.headerWidth)
            ZStack {
                if case let .success(events) = result {
                    PianoRoll(events: events, start: window.start, bars: window.count, tint: tint,
                              dimmed: !isAudible, position: position,
                              rests: app.rests(for: layer.id), boundaries: sectionStarts)
                } else if result == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Label("This layer has an error. The last working version still plays.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(Theme.danger.opacity(0.9))
                }
                Playhead(bars: window.count, position: position)
            }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.lane))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(height: 88)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? tint.opacity(0.09) : .clear)
                .strokeBorder(isSelected ? tint.opacity(0.55) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { app.selectedLayerID = layer.id; app.inspectsSection = false }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var sectionStarts: [Int] {
        var bar = 0
        return app.song.sections.map { section in defer { bar += section.bars }; return bar }
    }

    /// Busiest bar where the layer plays, so a 4-bar intro does not dilute the count.
    private func eventsPerBar(_ events: [NoteEvent]) -> Int {
        var counts: [Int: Int] = [:]
        for event in events { counts[Int(event.begin), default: 0] += 1 }
        return counts.values.max() ?? 0
    }
}

private struct Playhead: View {
    let bars: Int
    let position: Double?

    var body: some View {
        GeometryReader { geo in
            if let position {
                Rectangle().fill(Theme.playhead.opacity(0.75)).frame(width: 1.5)
                    .offset(x: geo.size.width * CGFloat(position / Double(bars)))
                    .shadow(color: .white.opacity(0.6), radius: 3)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct EmptySheet: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.quarternote.3").font(.system(size: 30)).foregroundStyle(Theme.faint)
            Text("No layers yet").font(.headline).foregroundStyle(Theme.text)
            Text("Describe a sound to the agent, or add a layer by hand.")
                .font(.callout).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
