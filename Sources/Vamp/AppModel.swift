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
    var seconds: Double = 0
    var songBefore: Song
}

@MainActor @Observable
final class AppModel {
    let engine = StrudelEngine()

    private(set) var song: Song
    var selectedLayerID: String?
    var bars = 4 { didSet { scheduleAnalysis() } }
    private(set) var analysis: [String: Result<[NoteEvent], LayerError>] = [:]
    private(set) var chat: [ChatEntry] = []
    private(set) var undoStack: [Song] = []
    private(set) var redoStack: [Song] = []

    var backend: BackendKind {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: "backend"); model = backend.models.first?.id ?? "" }
    }
    var model: String { didSet { UserDefaults.standard.set(model, forKey: "model.\(backend.rawValue)") } }

    @ObservationIgnored private var lastGood: [String: String] = [:]
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var agentTask: Task<Void, Never>?
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

    var isAgentWorking: Bool { chat.last?.state == .working }
    var sessionCost: Double { chat.compactMap(\.costUSD).reduce(0, +) }

    // MARK: Editing

    /// Every change goes through here, so undo, analysis, playback and saving stay in step.
    func update(_ label: String = "", coalesce: Bool = false, _ change: (inout Song) -> Void) {
        var next = song
        change(&next)
        guard next != song else { return }
        if !coalesce || Date().timeIntervalSince(lastTypingSnapshot) > 1.5 {
            undoStack.append(song)
            if undoStack.count > 200 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        if coalesce { lastTypingSnapshot = Date() }
        song = next
        if let id = selectedLayerID, song.index(of: id) == nil { selectedLayerID = song.layers.first?.id }
        scheduleAnalysis(delay: coalesce ? 0.25 : 0)
        scheduleSave()
    }

    func updateLayer(_ id: String, coalesce: Bool = false, _ change: (inout Layer) -> Void) {
        update(coalesce: coalesce) { song in
            guard let i = song.index(of: id) else { return }
            change(&song.layers[i])
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

    private func replace(with newSong: Song) {
        song = newSong
        if let id = selectedLayerID, song.index(of: id) == nil { selectedLayerID = song.layers.first?.id }
        scheduleAnalysis(delay: 0)
        scheduleSave()
    }

    func newSong() {
        update { $0 = Song(title: "Untitled", bpm: 110, layers: []) }
    }

    // MARK: Playback

    func togglePlay() {
        engine.isPlaying ? engine.stop() : playCurrent()
    }

    private func playCurrent() {
        var playable = song
        for i in playable.layers.indices where lastGood[playable.layers[i].id] == nil {
            playable.layers[i].muted = true
        }
        guard let code = playable.composedCode(codeOverrides: lastGood) else { engine.stop(); return }
        engine.play(code)
    }

    /// The program as Strudel will run it, for copying into strudel.cc.
    var exportCode: String { song.composedCode() ?? "// Every layer is muted." }

    // MARK: Analysis

    private func scheduleAnalysis(delay: Double = 0) {
        analysisTask?.cancel()
        analysisTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, engine.status == .ready else { return }
            let result = await engine.analyze(song.layers, cycles: bars)
            guard !Task.isCancelled else { return }
            analysis = result
            for (id, value) in result {
                if case .success = value, let layer = song.layers.first(where: { $0.id == id }) { lastGood[id] = layer.code }
            }
            if engine.isPlaying { playCurrent() }
        }
    }

    /// Called when the engine finishes loading.
    func engineDidBecomeReady() { scheduleAnalysis(delay: 0) }

    // MARK: Agent

    func send(_ request: String) {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAgentWorking else { return }
        let kind = backend, chosen = model
        let modelLabel = kind.models.first { $0.id == chosen }?.label ?? chosen
        chat.append(ChatEntry(request: text, backend: modelLabel, songBefore: song))
        let history = chat.filter { $0.state == .done }.map { Turn(request: $0.request, summary: $0.summary) }
        let started = Date()
        let engine = engine

        agentTask = Task {
            do {
                let result = try await AgentSession.run(
                    request: text, song: song, history: history,
                    ask: { system, user in try await Backends.ask(kind: kind, model: chosen, system: system, user: user) },
                    validate: { candidate in
                        let found = await engine.analyze(candidate.layers, cycles: 4)
                        return found.compactMapValues { if case let .failure(e) = $0 { e.message } else { nil } }
                    })
                update { $0 = result.song }
                finishEntry { entry in
                    entry.state = .done
                    entry.summary = result.summary
                    entry.changes = result.changes
                    entry.costUSD = result.costUSD
                    entry.tokens = result.inputTokens + result.outputTokens
                }
                if case let .added(id)? = result.changes.first(where: { if case .added = $0 { true } else { false } }) {
                    selectedLayerID = id
                }
            } catch is CancellationError {
                finishEntry { $0.state = .failed("Stopped.") }
            } catch {
                finishEntry { $0.state = .failed(error.localizedDescription) }
            }
            finishEntry { $0.seconds = Date().timeIntervalSince(started) }
            scheduleSave()
        }
    }

    func cancelAgent() { agentTask?.cancel() }

    /// Puts the song back to how it was before this prompt.
    func revert(_ entry: ChatEntry) { update { $0 = entry.songBefore } }

    func clearChat() {
        chat.removeAll { $0.state != .working }
        scheduleSave()
    }

    private func finishEntry(_ change: (inout ChatEntry) -> Void) {
        guard !chat.isEmpty else { return }
        change(&chat[chat.count - 1])
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            Persistence.save(.init(song: song, chat: Array(chat.suffix(100))))
        }
    }
}
