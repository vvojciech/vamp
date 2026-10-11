import Foundation
import Combine
import SwiftUI
import VampCore

/// One prompt in the agent log, with the song as it was before, so it can be undone.
struct ChatEntry: Identifiable, Codable, Equatable {
    enum State: Codable, Equatable { case working, done, failed(String) }

    var id = UUID()
    var request: String
    var backend: String
    var state: State = .working
    var summary = ""
    var changes: [EditPlan.Change] = []
    var costUSD: Double?
    var tokens = 0
    var attempts: Int?
    var seconds: Double = 0
    var songBefore: Song
}

/// The app's state. An ObservableObject on purpose, not @Observable: Observation keeps
/// per-thread access lists, and a task that read the model inside a nested run loop corrupted
/// them twice (EXC_BAD_ACCESS in ObservationTracking._AccessList.addAccess).
@MainActor
final class AppModel: ObservableObject {
    let engine = StrudelEngine()

    @Published private(set) var song: Song
    @Published var selectedLayerID: String? { didSet { if selectedLayerID != nil { inspectsSection = false } } }
    @Published var selectedSectionID: String? { didSet { if selectedSectionID == nil { loopsSection = false } } }
    /// True when the inspector shows the selected section instead of the selected layer.
    @Published var inspectsSection = false
    /// Play and show only the selected section.
    @Published var loopsSection = false { didSet { scheduleAnalysis(); if engine.isPlaying { playCurrent() } } }
    /// View length when the song has no sections.
    @Published var bars = 4 { didSet { scheduleAnalysis() } }
    /// Where Play starts in an arranged song, in bars. Set by the ruler, the section buttons and ← →.
    @Published var cursorBar = 0
    /// The bar the current playback started from. Edits during playback keep it, so the music continues.
    private(set) var playStartBar = 0
    @Published private(set) var analysis: [String: Result<[NoteEvent], LayerError>] = [:]
    @Published var chat: [ChatEntry] = []
    @Published private(set) var undoStack: [Song] = []
    @Published private(set) var redoStack: [Song] = []

    @Published var backend: BackendKind {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: "backend"); model = backend.models.first?.id ?? "" }
    }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "model.\(backend.rawValue)") } }

    /// Last program per layer that ran, so a typo never silences a layer.
    private var lastGood: [String: String] = [:]
    private var analysisTask: Task<Void, Never>?
    var agentTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var lastTypingSnapshot = Date.distantPast
    /// Views read engine state through the app model, so pass its changes on.
    private var engineChanges: AnyCancellable?

    init() {
        let saved = Persistence.load()
        song = saved?.song ?? .starter
        chat = (saved?.chat ?? []).filter { $0.state != .working }
        let kind = BackendKind(rawValue: UserDefaults.standard.string(forKey: "backend") ?? "") ?? .claudeCLI
        backend = kind
        model = UserDefaults.standard.string(forKey: "model.\(kind.rawValue)") ?? kind.models.first?.id ?? ""
        selectedLayerID = song.layers.first?.id
        engineChanges = engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        scheduleAnalysis(delay: 0)
    }

    // MARK: View window

    /// The looped section, when looping is on.
    var loopedSection: Section? { loopsSection ? selectedSectionID.flatMap(song.section) : nil }

    /// The bars the sheet shows: (first bar, count).
    var window: (start: Int, count: Int) {
        if let looped = loopedSection, let index = song.sections.firstIndex(of: looped) {
            return (song.sections[..<index].map(\.bars).reduce(0, +), looped.bars)
        }
        return (0, song.totalBars ?? bars)
    }

    /// Bar ranges where a layer rests, for shading in its lane.
    func rests(for layerID: String) -> [Range<Double>] {
        var start = 0, ranges: [Range<Double>] = []
        for section in song.sections {
            if !section.layerIDs.contains(layerID) { ranges.append(Double(start)..<Double(start + section.bars)) }
            start += section.bars
        }
        return ranges
    }

    // MARK: Editing

    /// Every change goes through here, so undo, analysis, playback and saving stay in step.
    func update(coalesce: Bool = false, _ change: (inout Song) -> Void) {
        var next = song
        change(&next)
        guard next != song else { return }
        if !coalesce || Date().timeIntervalSince(lastTypingSnapshot) > 1.5 {
            undoStack.append(song)
            if undoStack.count > 200 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        if coalesce { lastTypingSnapshot = Date() }
        replace(with: next, delay: coalesce ? 0.25 : 0)
    }

    func updateLayer(_ id: String, coalesce: Bool = false, _ change: (inout Layer) -> Void) {
        update(coalesce: coalesce) { song in
            guard let i = song.index(of: id) else { return }
            change(&song.layers[i])
        }
    }

    func updateSection(_ id: String, coalesce: Bool = false, _ change: (inout Section) -> Void) {
        update(coalesce: coalesce) { song in
            guard let i = song.sections.firstIndex(where: { $0.id == id }) else { return }
            change(&song.sections[i])
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(song)
        replace(with: previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(song)
        replace(with: next)
    }

    private func replace(with newSong: Song, delay: Double = 0) {
        song = newSong
        if let id = selectedLayerID, song.index(of: id) == nil { selectedLayerID = song.layers.first?.id }
        if let id = selectedSectionID, song.section(id) == nil { selectedSectionID = nil; inspectsSection = false }
        scheduleAnalysis(delay: delay)
        scheduleSave()
    }

    func newSong() {
        update { $0 = Song(title: "Untitled", bpm: 110, layers: []) }
    }

    // MARK: Playback

    func togglePlay() {
        if engine.isPlaying { engine.stop(); return }
        start()
    }

    /// Starts playback from the cursor. Stops first if needed, because Strudel counts from 0 on each start.
    func start() {
        if engine.isPlaying { engine.stop() }
        playStartBar = song.sections.isEmpty || loopsSection ? 0 : min(cursorBar, max((song.totalBars ?? 1) - 1, 0))
        guard lastGood.isEmpty else { playCurrent(); return }
        // Nothing checked yet (for example just after launch): check first, then play.
        let snapshot = song, range = window
        Task {
            record(await analyze(snapshot, cycles: range.start + range.count), of: snapshot)
            playCurrent()
        }
    }

    func playCurrent() {
        var playable = song
        for i in playable.layers.indices where lastGood[playable.layers[i].id] == nil {
            playable.layers[i].muted = true
        }
        // A song with sections plays once, with two silent bars so the ending rings out.
        let tail = 2
        let code = playable.composedCode(codeOverrides: lastGood, tailBars: tail, startBar: playStartBar,
                                         onlySection: loopedSection?.id)
        guard let code else { engine.stop(); return }
        engine.stopAtCycle = song.playbackEnd(tailBars: tail, loopingSection: loopedSection?.id, startBar: playStartBar)
        engine.play(code)
    }

    /// The program as Strudel will run it, for copying into strudel.cc.
    var exportCode: String { song.composedCode() ?? "// Every layer is muted." }

    // MARK: Analysis

    /// Note events for each layer's full program, over the first `cycles` bars.
    func analyze(_ song: Song, cycles: Int) async -> [String: Result<[NoteEvent], LayerError>] {
        let programs = song.layers.map { layer -> Layer in
            var copy = layer
            copy.code = song.program(for: layer) ?? "silence"
            return copy
        }
        return await engine.analyze(programs, cycles: max(cycles, 1))
    }

    /// Remembers which programs ran, taken from the song that was analysed, not a later one.
    private func record(_ result: [String: Result<[NoteEvent], LayerError>], of analysed: Song) {
        for (id, value) in result {
            guard case .success = value, let layer = analysed.layers.first(where: { $0.id == id }) else { continue }
            lastGood[id] = analysed.program(for: layer)
        }
    }

    private func scheduleAnalysis(delay: Double = 0) {
        analysisTask?.cancel()
        // Take a snapshot now; the task never reads the observable model after a suspension.
        let snapshot = song
        let range = window
        analysisTask = Task { [engine] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, engine.status == .ready else { return }
            let result = await analyze(snapshot, cycles: range.start + range.count)
            guard !Task.isCancelled else { return }
            analysis = result
            record(result, of: snapshot)
            if engine.isPlaying { playCurrent() }
        }
    }

    /// Called when the engine finishes loading.
    func engineDidBecomeReady() { scheduleAnalysis(delay: 0) }

    // MARK: Saving

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            Persistence.save(.init(song: song, chat: Array(chat.suffix(100))))
        }
    }
}
