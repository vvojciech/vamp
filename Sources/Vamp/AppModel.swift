import Foundation
import Observation
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
    /// Set for a polish run: the overall score after each round.
    var rounds: [RoundNote]?
}

struct RoundNote: Codable, Equatable {
    var number: Int
    var overall: Double
    var weakest: String
}

@MainActor @Observable
final class AppModel {
    let engine = StrudelEngine()

    private(set) var song: Song
    var selectedLayerID: String? { didSet { if selectedLayerID != nil { inspectsSection = false } } }
    var selectedSectionID: String? { didSet { if selectedSectionID == nil { loopsSection = false } } }
    /// True when the inspector shows the selected section instead of the selected layer.
    var inspectsSection = false
    /// Play and show only the selected section.
    var loopsSection = false { didSet { scheduleAnalysis(); if engine.isPlaying { playCurrent() } } }
    /// View length when the song has no sections.
    var bars = 4 { didSet { scheduleAnalysis() } }
    private(set) var analysis: [String: Result<[NoteEvent], LayerError>] = [:]
    /// Live measured scores, or the judged card from the latest polish round.
    var scorecard: Scorecard?
    /// True while `scorecard` includes the judge's view, until the song changes again.
    var scorecardJudged = false
    var chat: [ChatEntry] = []
    private(set) var undoStack: [Song] = []
    private(set) var redoStack: [Song] = []

    var backend: BackendKind {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: "backend"); model = backend.models.first?.id ?? "" }
    }
    var model: String { didSet { UserDefaults.standard.set(model, forKey: "model.\(backend.rawValue)") } }

    /// Last program per layer that ran, so a typo never silences a layer.
    @ObservationIgnored private var lastGood: [String: String] = [:]
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored var agentTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastTypingSnapshot = Date.distantPast

    init() {
        let saved = Persistence.load()
        song = saved?.song ?? .starter
        chat = (saved?.chat ?? []).filter { $0.state != .working }
        let kind = BackendKind(rawValue: UserDefaults.standard.string(forKey: "backend") ?? "") ?? .claudeCLI
        backend = kind
        model = UserDefaults.standard.string(forKey: "model.\(kind.rawValue)") ?? kind.models.first?.id ?? ""
        selectedLayerID = song.layers.first?.id
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
        guard lastGood.isEmpty else { playCurrent(); return }
        // Nothing checked yet (for example just after launch): check first, then play.
        Task {
            record(await analyze(song, cycles: window.start + window.count))
            playCurrent()
        }
    }

    func playCurrent() {
        var playable = song
        for i in playable.layers.indices where lastGood[playable.layers[i].id] == nil {
            playable.layers[i].muted = true
        }
        let code = playable.composedCode(codeOverrides: lastGood, onlySection: loopedSection?.id)
        guard let code else { engine.stop(); return }
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

    private func record(_ result: [String: Result<[NoteEvent], LayerError>]) {
        for (id, value) in result {
            guard case .success = value, let layer = song.layers.first(where: { $0.id == id }) else { continue }
            lastGood[id] = song.program(for: layer)
        }
    }

    private func scheduleAnalysis(delay: Double = 0) {
        analysisTask?.cancel()
        analysisTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, engine.status == .ready else { return }
            let result = await analyze(song, cycles: window.start + window.count)
            guard !Task.isCancelled else { return }
            analysis = result
            record(result)
            if !loopsSection && !isPolishing {
                scorecard = SongCritic.measure(song: song, events: result.compactMapValues { try? $0.get() }, bars: window.count)
                scorecardJudged = false
            }
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
