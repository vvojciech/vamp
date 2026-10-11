import Foundation
import Observation
import VampCore
import WebKit

/// One note or hit, as the score draws it. Times are in cycles (bars).
/// Hosts Strudel in a hidden web view. Strudel does the sound; Swift does everything visible.
@MainActor @Observable
final class StrudelEngine: NSObject, WKScriptMessageHandler {
    enum Status: Equatable { case loading, ready, failed(String) }

    private(set) var status: Status = .loading
    private(set) var isPlaying = false
    private(set) var lastPlayError: String?
    @ObservationIgnored let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 4, height: 4), configuration: config)
        super.init()
        config.userContentController.add(WeakHandler(self), name: "vamp")
        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "engine") {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        } else {
            status = .failed("The engine files are missing from the app bundle.")
        }
    }

    /// Note events per layer for the first `cycles` bars, or an error message per layer.
    func analyze(_ layers: [Layer], cycles: Int) async -> [String: Result<[NoteEvent], LayerError>] {
        let input = layers.map { ["id": $0.id, "code": $0.code] }
        guard let raw = try? await webView.callAsyncJavaScript(
            "return JSON.stringify(window.vamp.analyze(layers, cycles))",
            arguments: ["layers": input, "cycles": cycles], contentWorld: .page) as? String,
            let rows = try? JSONDecoder().decode([AnalysisRow].self, from: Data(raw.utf8))
        else { return [:] }
        var results: [String: Result<[NoteEvent], LayerError>] = [:]
        for row in rows {
            results[row.id] = row.error.map { .failure(LayerError(message: $0)) } ?? .success(row.events ?? [])
        }
        return results
    }

    func play(_ code: String) {
        lastPlayError = nil
        webView.callAsyncJavaScript("window.vamp.play(code)", arguments: ["code": code], in: nil, in: .page) { _ in }
        isPlaying = true
    }

    func stop() {
        webView.evaluateJavaScript("window.vamp.stop()")
        isPlaying = false
        clock = nil
    }

    /// Last clock reading from Strudel. The playhead extrapolates from it every frame.
    @ObservationIgnored private var clock: (cycle: Double, at: Date)?

    /// The playing position in cycles, or nil when stopped.
    func position(at date: Date, bpm: Double) -> Double? {
        guard isPlaying, let clock else { return nil }
        return clock.cycle + date.timeIntervalSince(clock.at) * bpm / 240
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let text = body["message"] as? String
        MainActor.assumeIsolated {
            switch type {
            case "ready": status = .ready
            case "time": if let cycle = body["cycle"] as? Double { clock = (cycle, Date()) }
            case "fatal": status = .failed(text ?? "The engine did not start.")
            case "playError": lastPlayError = text; isPlaying = false
            case "stopped": isPlaying = false; clock = nil
            // stderr is unbuffered, so the line survives even if the app is stopped right after.
            case "log": if let text { FileHandle.standardError.write(Data("[engine] \(text)\n".utf8)) }
            default: break
            }
        }
    }
}

struct LayerError: Error, Hashable { var message: String }

private struct AnalysisRow: Decodable {
    var id: String
    var events: [NoteEvent]?
    var error: String?
}

/// WKUserContentController keeps a strong reference to its handlers.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
