import AppKit
import SwiftUI

/// A plain-text code editor with Strudel colouring. AppKit's NSTextView, because
/// SwiftUI's TextEditor turns straight quotes into curly ones and breaks the code.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        let view = scroll.documentView as! NSTextView
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.font = Highlighter.font
        view.textColor = Highlighter.base
        view.insertionPointColor = NSColor(Theme.accent)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.string = text
        Highlighter.apply(to: view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let view = scroll.documentView as! NSTextView
        context.coordinator.text = $text
        if view.string != text {
            let selection = view.selectedRanges
            view.string = text
            view.selectedRanges = selection.filter { $0.rangeValue.upperBound <= (text as NSString).length }
            Highlighter.apply(to: view)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            Highlighter.apply(to: view)
            text.wrappedValue = view.string
        }
    }
}

private enum Highlighter {
    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    static let base = NSColor(white: 0.88, alpha: 1)
    static let rules: [(NSRegularExpression, NSColor)] = [
        (try! NSRegularExpression(pattern: #"\.?\b[a-zA-Z_]\w*(?=\()"#), NSColor(Color(hex: 0xA99BFF))),
        (try! NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#), NSColor(Color(hex: 0x3FD8C7))),
        (try! NSRegularExpression(pattern: #""[^"\n]*"|'[^'\n]*'|`[^`]*`"#), NSColor(Color(hex: 0xFFC15E))),
        (try! NSRegularExpression(pattern: #"//[^\n]*"#), NSColor(white: 0.45, alpha: 1)),
    ]

    static func apply(to view: NSTextView) {
        guard let storage = view.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: base], range: all)
        for (regex, color) in rules {
            for match in regex.matches(in: storage.string, range: all) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        storage.endEditing()
    }
}
