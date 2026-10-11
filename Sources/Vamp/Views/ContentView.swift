import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TransportBar()
                Divider().overlay(Theme.line)
                VSplitView {
                    SheetView().frame(minHeight: 220)
                    InspectorView().frame(minHeight: 150, idealHeight: 190, maxHeight: 480)
                }
            }
            Divider().overlay(Theme.line)
            AgentPanel().frame(width: 360)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.window)
        .background(EngineHost(webView: app.engine.webView).frame(width: 1, height: 1).opacity(0))
        .preferredColorScheme(.dark)
        .frame(minWidth: 1080, minHeight: 640)
        .onChange(of: app.engine.status) { _, status in
            if status == .ready {
                app.engineDidBecomeReady()
                DevHooks.run(app)
            }
        }
        .onAppear { keyMonitor = Self.installTransportKeys(app) }
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
    }

    /// Space plays and stops; ← and → jump between sections. Not while the musician types.
    private static func installTransportKeys(_ app: AppModel) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Arrow keys carry the numericPad and function flags, so check only real modifiers.
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty, !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
            switch event.keyCode {
            case 49: MainActor.assumeIsolated { app.togglePlay() }
            case 123: MainActor.assumeIsolated { app.previousSection() }
            case 124: MainActor.assumeIsolated { app.nextSection() }
            default: return event
            }
            return nil
        }
    }
}

/// Keeps the engine's web view in the window, so WebKit treats it as visible and keeps audio running.
private struct EngineHost: NSViewRepresentable {
    let webView: NSView
    func makeNSView(context: Context) -> NSView { webView }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
