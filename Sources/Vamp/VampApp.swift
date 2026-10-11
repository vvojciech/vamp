import SwiftUI

/// Quits cleanly on SIGTERM as well as on ⌘Q: the session is saved and WebKit closes its audio,
/// instead of the process being cut off with audio streams open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppModel?
    private var termination: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termination = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { app?.saveNow() }
    }
}

@main
struct VampApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppModel()

    var body: some Scene {
        Window("Vamp", id: "main") {
            ContentView()
                .environmentObject(app)
                .onAppear { delegate.app = app }
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
                .environmentObject(app)
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
