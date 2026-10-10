import SwiftUI

@main
struct VampApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        Window("Vamp", id: "main") {
            ContentView()
                .environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Song") { app.newSong() }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { undoOrForward("undo:") { app.undo() } }
                    .keyboardShortcut("z")
                Button("Redo") { undoOrForward("redo:") { app.redo() } }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Playback") {
                Button(app.engine.isPlaying ? "Stop" : "Play") { app.togglePlay() }
                    .keyboardShortcut(.return, modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }

    /// Text fields keep their own typing undo. Everywhere else, undo moves through song versions.
    private func undoOrForward(_ action: String, song: () -> Void) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable {
            NSApp.sendAction(Selector(action), to: nil, from: nil)
        } else {
            song()
        }
    }
}
