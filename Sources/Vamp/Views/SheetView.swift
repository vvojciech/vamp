import SwiftUI
import VampCore

/// The music sheet: a bar ruler, then one lane per layer, all sharing one playhead.
struct SheetView: View {
    @Environment(AppModel.self) private var app
    static let headerWidth: CGFloat = 214

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                TimelineView(.animation(paused: !app.engine.isPlaying)) { timeline in
                    let position = app.engine.position(at: timeline.date, bpm: app.song.bpm)
                    VStack(spacing: 6) {
                        Ruler(bars: app.bars, position: position)
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
    let bars: Int
    let position: Double?

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: SheetView.headerWidth)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(0..<bars, id: \.self) { bar in
                        Text("\(bar + 1)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.faint)
                            .offset(x: geo.size.width / CGFloat(bars) * CGFloat(bar) + 4, y: 3)
                    }
                    if let position {
                        let x = geo.size.width * CGFloat(position.truncatingRemainder(dividingBy: Double(bars)) / Double(bars))
                        Capsule().fill(Theme.playhead).frame(width: 9, height: 9).offset(x: x - 4.5, y: 4)
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

    private var isSelected: Bool { app.selectedLayerID == layer.id }
    private var isAudible: Bool { app.song.audibleLayers.contains { $0.id == layer.id } }

    var body: some View {
        let tint = Theme.color(for: layer.role)
        let result = app.analysis[layer.id]
        HStack(spacing: 12) {
            LaneHeader(layer: layer,
                       error: result.flatMap { if case let .failure(e) = $0 { e.message } else { nil } },
                       eventsPerBar: result.flatMap { if case let .success(events) = $0 { events.count / max(app.bars, 1) } else { nil } })
                .frame(width: SheetView.headerWidth)
            ZStack {
                if case let .success(events) = result {
                    PianoRoll(events: events, bars: app.bars, tint: tint, dimmed: !isAudible, position: position)
                } else if result == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Label("This layer has an error. The last working version still plays.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(Theme.danger.opacity(0.9))
                }
                Playhead(bars: app.bars, position: position)
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
        .onTapGesture { app.selectedLayerID = layer.id }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

private struct Playhead: View {
    let bars: Int
    let position: Double?

    var body: some View {
        GeometryReader { geo in
            if let position {
                let x = geo.size.width * CGFloat(position.truncatingRemainder(dividingBy: Double(bars)) / Double(bars))
                Rectangle().fill(Theme.playhead.opacity(0.75)).frame(width: 1.5).offset(x: x)
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

/// Starts a new layer from a small template for its role.
struct AddLayerMenu: View {
    @Environment(AppModel.self) private var app

    static let templates: [(LayerRole, String)] = [
        (.drums, "s(\"bd*4, [~ sd]*2, hh*8\")"),
        (.percussion, "s(\"[~ rm]*2, perc(3,8)\").gain(0.7)"),
        (.bass, "note(\"<c2 g1 ab1 bb1>*4\").s(\"sawtooth\").lpf(700).decay(0.2).sustain(0)"),
        (.chords, "chord(\"<Cm7 Ab^7 Fm7 G7>\").voicing().s(\"triangle\").attack(0.05).release(0.6).room(0.4)"),
        (.pad, "chord(\"<Cm9 Fm9>\").voicing().s(\"supersaw\").attack(1).release(2).lpf(900).room(0.7).gain(0.3)"),
        (.lead, "n(\"<0 [2 4] 3 [4 7]>\").scale(\"C4:minor\").s(\"square\").lpf(2000).delay(0.3)"),
        (.arp, "n(\"0 2 4 7 4 2\").fast(2).scale(\"C4:minor\").s(\"triangle\").decay(0.15).sustain(0)"),
        (.fx, "s(\"white\").struct(\"~ ~ ~ x\").hpf(4000).decay(0.4).sustain(0).gain(0.3)"),
    ]

    var body: some View {
        Menu {
            ForEach(Self.templates, id: \.0) { role, code in
                Button { add(role, code) } label: { Label(role.label, systemImage: Theme.symbol(for: role)) }
            }
        } label: {
            Label("Add layer", systemImage: "plus")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.muted)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func add(_ role: LayerRole, _ code: String) {
        var newID = ""
        app.update { song in
            newID = song.uniqueID(for: role.label)
            song.layers.append(Layer(id: newID, name: role.label, role: role, code: code))
        }
        app.selectedLayerID = newID
    }
}
