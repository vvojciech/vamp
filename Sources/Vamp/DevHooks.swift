import AppKit
import SwiftUI

/// Developer hooks for checks without a mouse, read from the environment at launch:
///   VAMP_PLAY=1            start playback once the engine is ready
///   VAMP_PROMPT="..."      send this prompt to the agent once the engine is ready
///   VAMP_PROMPTS=/p.txt    then send each line of this file in order (blank lines and # comments skipped)
///   VAMP_SNAPSHOT=/a.png   render the window to a PNG (after VAMP_SNAPSHOT_DELAY seconds, default 4)
///   VAMP_SELECT=layer-id   select this layer before the snapshot
///   VAMP_SEEK=bar          move the play cursor to this bar (before VAMP_PLAY)
///   VAMP_SESSION=/s.json   load and save the session here instead of Application Support
///   VAMP_QUIT=1            quit once the agent has finished and the session is saved
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
        if env["VAMP_PLAY"] == "1" { app.togglePlay() }
        var queue = env["VAMP_PROMPT"].map { [$0] } ?? []
        if let path = env["VAMP_PROMPTS"], let file = try? String(contentsOfFile: path, encoding: .utf8) {
            queue += prompts(fromFile: file)
        }
        let quit = env["VAMP_QUIT"] == "1"
        Task {
            // Each prompt waits for the one before, like a musician reading each answer first.
            for prompt in queue {
                app.send(prompt)
                while app.isAgentWorking { try? await Task.sleep(for: .seconds(1)) }
            }
            guard quit else { return }
            try? await Task.sleep(for: .seconds(2))  // The session save waits 0.8 s after the last change.
            NSApp.terminate(nil)
        }
        guard let path = env["VAMP_SNAPSHOT"] else { return }
        let delay = Double(env["VAMP_SNAPSHOT_DELAY"] ?? "") ?? 4
        Task {
            try? await Task.sleep(for: .seconds(delay))
            snapshot(to: URL(fileURLWithPath: path))
        }
    }

    private static func snapshot(to url: URL) {
        guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
