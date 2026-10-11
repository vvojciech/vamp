import AppKit
import SwiftUI

/// Developer hooks for checks without a mouse, read from the environment at launch:
///   VAMP_PLAY=1            start playback once the engine is ready
///   VAMP_PROMPT="..."      send this prompt to the agent once the engine is ready
///   VAMP_PROMPTS=/p.txt    then send each line of this file in order (blank lines and # comments skipped)
///   VAMP_SNAPSHOT=/a.png   render the window to a PNG (after VAMP_SNAPSHOT_DELAY seconds, default 4)
///   VAMP_SELECT=layer-id   select this layer before the snapshot
///   VAMP_SEEK=bar          move the play cursor to this bar (before VAMP_PLAY)
///   VAMP_LEVELS=1          write the audio output level to stderr twice a second
///   VAMP_JS="return ..."   run this script in the engine page once it is ready and log the result
///   VAMP_LAYER_LEVELS=/l   after the prompts, play each layer alone and write its peak level as JSON
///   VAMP_SESSION=/s.json   load and save the session here instead of Application Support
///   VAMP_QUIT=1            quit once the agent has finished and the session is saved
///   VAMP_DONE_FILE=/d      write this file at that point instead, and keep the window open
@MainActor
enum DevHooks {
    /// One prompt per line. Blank lines and lines that start with # are skipped.
    nonisolated static func prompts(fromFile contents: String) -> [String] {
        contents.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func run(_ app: AppModel) {
        let env = ProcessInfo.processInfo.environment
        if let id = env["VAMP_SELECT"] { app.selectedLayerID = id }
        if let bar = env["VAMP_SEEK"].flatMap(Int.init) { app.seek(toBar: bar) }
        if let script = env["VAMP_JS"] {
            Task {
                let result = try? await app.engine.webView.callAsyncJavaScript(script, arguments: [:], contentWorld: .page)
                FileHandle.standardError.write(Data("[js] \(result.map { "\($0)" } ?? "nil")\n".utf8))
            }
        }
        if env["VAMP_LEVELS"] == "1" {
            Task {
                while true {
                    try? await Task.sleep(for: .milliseconds(500))
                    let level = await app.engine.level()
                    FileHandle.standardError.write(Data(String(format: "[level] peak %.4f rms %.4f\n", level.peak, level.rms).utf8))
                }
            }
        }
        if env["VAMP_PLAY"] == "1" { app.togglePlay() }
        var queue = env["VAMP_PROMPT"].map { [$0] } ?? []
        if let path = env["VAMP_PROMPTS"], let file = try? String(contentsOfFile: path, encoding: .utf8) {
            queue += prompts(fromFile: file)
        }
        let quit = env["VAMP_QUIT"] == "1"
        let doneFile = env["VAMP_DONE_FILE"]
        Task {
            // Each prompt waits for the one before, like a musician reading each answer first.
            for prompt in queue {
                app.send(prompt)
                while app.isAgentWorking { try? await Task.sleep(for: .seconds(1)) }
            }
            if let path = env["VAMP_LAYER_LEVELS"] {
                let levels = await measureLayers(app)
                try? JSONEncoder().encode(levels).write(to: URL(fileURLWithPath: path))
            }
            guard quit || doneFile != nil else { return }
            try? await Task.sleep(for: .seconds(2))  // The session save waits 0.8 s after the last change.
            if let doneFile { FileManager.default.createFile(atPath: doneFile, contents: Data("done\n".utf8)) }
            if quit { NSApp.terminate(nil) }
        }
        guard let path = env["VAMP_SNAPSHOT"] else { return }
        let delay = Double(env["VAMP_SNAPSHOT_DELAY"] ?? "") ?? 4
        Task {
            try? await Task.sleep(for: .seconds(delay))
            snapshot(to: URL(fileURLWithPath: path))
        }
    }

    /// Plays each layer alone from where it is first heard and returns its peak level.
    /// A peak near 0 means the layer is silent: a missing sample, a failed soundfont or a broken effect.
    static func measureLayers(_ app: AppModel) async -> [String: Double] {
        var peaks: [String: Double] = [:]
        for layer in app.song.layers {
            guard let start = app.song.firstBar(whereLayerPlays: layer.id) else { continue }
            var alone = app.song
            for i in alone.layers.indices {
                alone.layers[i].solo = alone.layers[i].id == layer.id
                alone.layers[i].muted = false
            }
            guard let code = alone.composedCode(startBar: start) else { continue }
            app.engine.stopAtCycle = nil
            app.engine.play(code)
            // Two bars, between 3 and 6 seconds; a soundfont's first notes can load late.
            let end = Date().addingTimeInterval(min(max(2 * 240 / alone.bpm, 3), 6))
            var peak = 0.0
            while Date() < end {
                try? await Task.sleep(for: .milliseconds(200))
                peak = max(peak, await app.engine.level().peak)
            }
            app.engine.stop()
            try? await Task.sleep(for: .milliseconds(500))  // let reverb tails fade before the next layer
            peaks[layer.id] = peak
        }
        return peaks
    }

    private static func snapshot(to url: URL) {
        guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
