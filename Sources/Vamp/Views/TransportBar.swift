import AppKit
import SwiftUI
import VampCore

/// Play, title, tempo, view length, undo and export.
struct TransportBar: View {
    @Environment(AppModel.self) private var app
    @State private var copied = false

    var body: some View {
        HStack(spacing: 16) {
            PlayButton()

            TextField("Title", text: Binding(
                get: { app.song.title },
                set: { title in app.update(coalesce: true) { $0.title = title } }))
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: 260)

            TempoControl()

            Picker("Bars", selection: Binding(get: { app.bars }, set: { app.bars = $0 })) {
                ForEach([1, 2, 4, 8], id: \.self) { Text("\($0) bar\($0 == 1 ? "" : "s")").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("How many bars the sheet shows")

            Spacer()

            EngineStatus()

            HStack(spacing: 2) {
                Button { app.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(app.undoStack.isEmpty).help("Undo (⌘Z)")
                Button { app.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(app.redoStack.isEmpty).help("Redo (⇧⌘Z)")
            }
            .buttonStyle(.borderless)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.exportCode, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(minWidth: 92)
            }
            .buttonStyle(.borderless)
            .help("Copy the whole song as Strudel code, ready for strudel.cc")
        }
        .foregroundStyle(Theme.muted)
        .padding(.leading, 84) // room for the window buttons in the hidden title bar
        .padding(.trailing, 18)
        .frame(height: 60)
        .background(Theme.panel)
    }
}

private struct PlayButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let playing = app.engine.isPlaying
        Button { app.togglePlay() } label: {
            Image(systemName: playing ? "stop.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: 38, height: 38)
                .background(Circle().fill(playing ? Color.white : Theme.accent))
                .shadow(color: Theme.accent.opacity(playing ? 0 : 0.45), radius: 8)
        }
        .buttonStyle(.plain)
        .disabled(app.engine.status != .ready)
        .help(playing ? "Stop (Space)" : "Play (Space)")
        .accessibilityLabel(playing ? "Stop" : "Play")
    }
}

private struct TempoControl: View {
    @Environment(AppModel.self) private var app
    @State private var dragStart: Double?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "metronome").font(.system(size: 12))
            Text("\(Int(app.song.bpm.rounded()))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(minWidth: 30)
            Text("BPM").font(.system(size: 10.5, weight: .medium))
            Stepper("Tempo", value: Binding(
                get: { app.song.bpm },
                set: { bpm in app.update(coalesce: true) { $0.bpm = min(max(bpm.rounded(), Song.bpmRange.lowerBound), Song.bpmRange.upperBound) } }),
                in: Song.bpmRange, step: 1)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
        .gesture(DragGesture().onChanged { drag in
            let start = dragStart ?? app.song.bpm
            dragStart = start
            let bpm = min(max((start - drag.translation.height / 3).rounded(), Song.bpmRange.lowerBound), Song.bpmRange.upperBound)
            app.update(coalesce: true) { $0.bpm = bpm }
        }.onEnded { _ in dragStart = nil })
        .help("Drag up or down to change the tempo")
    }
}

private struct EngineStatus: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.engine.status {
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading sounds…").font(.system(size: 11.5))
            }
        case let .failed(message):
            Label("Engine error", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5)).foregroundStyle(Theme.danger).help(message)
        case .ready:
            if let error = app.engine.lastPlayError {
                Label("Playback error", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.danger).help(error)
            }
        }
    }
}
