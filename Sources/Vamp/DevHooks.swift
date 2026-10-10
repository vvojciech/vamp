import AppKit
import SwiftUI

/// Developer hooks for checks without a mouse, read from the environment at launch:
///   VAMP_PLAY=1            start playback once the engine is ready
///   VAMP_PROMPT="..."      send this prompt to the agent once the engine is ready
///   VAMP_SNAPSHOT=/a.png   render the window to a PNG (after VAMP_SNAPSHOT_DELAY seconds, default 4)
///   VAMP_SELECT=layer-id   select this layer before the snapshot
@MainActor
enum DevHooks {
    static func run(_ app: AppModel) {
        let env = ProcessInfo.processInfo.environment
        if let id = env["VAMP_SELECT"] { app.selectedLayerID = id }
        if env["VAMP_PLAY"] == "1" { app.togglePlay() }
        if let prompt = env["VAMP_PROMPT"] { app.send(prompt) }
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
