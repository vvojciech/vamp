import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TransportBar()
                Divider().overlay(Theme.line)
                VSplitView {
                    SheetView().frame(minHeight: 220)
                    InspectorView().frame(minHeight: 170, idealHeight: 250)
                }
            }
            Divider().overlay(Theme.line)
            AgentPanel().frame(width: 360)
        }
        .background(Theme.window)
        .background(EngineHost(webView: app.engine.webView).frame(width: 1, height: 1).opacity(0))
        .preferredColorScheme(.dark)
        .frame(minWidth: 1080, minHeight: 640)
        .onChange(of: app.engine.status) { _, status in
            if status == .ready { app.engineDidBecomeReady() }
        }
        .onAppear { keyMonitor = Self.installSpaceBar(app) }
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
    }

    /// Space plays and stops, unless the musician is typing in a text field.
    private static func installSpaceBar(_ app: AppModel) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
            MainActor.assumeIsolated { app.togglePlay() }
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
