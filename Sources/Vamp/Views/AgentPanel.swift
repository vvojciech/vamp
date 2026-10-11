import SwiftUI
import VampCore

/// The conversation with the agent: what was asked, what changed, what it cost.
struct AgentPanel: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if app.sessionCost > 0 {
                    Text(String(format: "$%.3f this session", app.sessionCost))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.faint)
                }
                if !app.chat.isEmpty {
                    Button { app.clearChat() } label: { Image(systemName: "eraser") }
                        .buttonStyle(.borderless).foregroundStyle(Theme.faint).help("Clear the log")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider().overlay(Theme.line)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if app.chat.isEmpty { Suggestions() }
                        ForEach(app.chat) { entry in
                            EntryView(entry: entry).id(entry.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: app.chat.last) { _, last in
                    if let last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            PromptComposer()
        }
        .background(Theme.panel)
    }
}

private struct Suggestions: View {
    @EnvironmentObject private var app: AppModel
    private let ideas = ["Compose a full song from this loop: intro, verses, choruses, a breakdown and an outro",
                         "Compose a warm lo-fi song with Rhodes-like piano, vinyl drums and a sax hook",
                         "Add a shuffling hi-hat groove", "Make it darker and slower", "Add a dreamy pad under everything"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe a change in plain words, or ask for a whole song. The agent edits only what it needs to, and you can undo any change.")
                .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(ideas, id: \.self) { idea in
                Button { app.send(idea) } label: {
                    Text(idea).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.raised))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct EntryView: View {
    @EnvironmentObject private var app: AppModel
    let entry: ChatEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.request)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
            switch entry.state {
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Composing with \(entry.backend)…").font(.callout).foregroundStyle(Theme.muted)
                }
                .padding(.leading, 4)
            case .done:
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.summary).font(.callout).foregroundStyle(Theme.text.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    ChangeChips(changes: entry.changes, songs: [app.song, entry.songBefore])
                    Footer(entry: entry)
                }
                .padding(.leading, 4)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(Theme.danger).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { app.send(entry.request) }
                        .buttonStyle(.borderless).font(.callout).disabled(app.isAgentWorking)
                }
                .padding(.leading, 4)
            }
        }
    }
}

private struct ChangeChips: View {
    static let visible = 8
    let changes: [EditPlan.Change]
    /// The song now, then the song before the prompt, for layers that no longer exist.
    let songs: [Song]

    var body: some View {
        if !changes.isEmpty {
            Flow(spacing: 6) {
                // A whole song makes dozens of changes; show the first few and count the rest.
                ForEach(Array(changes.prefix(Self.visible).enumerated()), id: \.offset) { _, change in
                    let (symbol, text, tint) = describe(change)
                    Label(text, systemImage: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.13)))
                }
                if changes.count > Self.visible {
                    Text("+\(changes.count - Self.visible) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.raised))
                        .help(changes.dropFirst(Self.visible).map { describe($0).1 }.joined(separator: ", "))
                }
            }
        }
    }

    private func layer(_ id: String) -> Layer? {
        songs.lazy.compactMap { $0.layers.first { $0.id == id } }.first
    }

    private func sectionName(_ id: String) -> String {
        songs.lazy.compactMap { $0.section(id)?.name }.first ?? id
    }

    private func describe(_ change: EditPlan.Change) -> (String, String, Color) {
        func name(_ id: String) -> String { layer(id)?.name ?? id }
        func tint(_ id: String) -> Color { layer(id).map { Theme.color(for: $0.role) } ?? Theme.muted }
        switch change {
        case let .added(id): return ("plus", name(id), tint(id))
        case let .changed(id): return ("pencil", name(id), tint(id))
        case let .removed(id): return ("minus", name(id), Theme.muted)
        case .tempo: return ("metronome", "Tempo", Theme.muted)
        case .title: return ("textformat", "Title", Theme.muted)
        case let .sectionAdded(id): return ("plus.rectangle", sectionName(id), Theme.sectionTint)
        case let .sectionChanged(id): return ("rectangle.and.pencil.and.ellipsis", sectionName(id), Theme.sectionTint)
        case let .sectionRemoved(id): return ("minus.rectangle", sectionName(id), Theme.muted)
        }
    }
}

/// Lays chips out left to right and wraps to a new line when the row is full.
private struct Flow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.indices.isEmpty && current.width + spacing + size.width > width {
                rows.append(current)
                current = ([], current.y + current.height + spacing, 0, 0)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

private struct Footer: View {
    @EnvironmentObject private var app: AppModel
    let entry: ChatEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(meta).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.faint)
            Spacer()
            Button { app.revert(entry) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(Theme.muted)
                .help("Put the song back to how it was before this prompt")
        }
    }

    private var meta: String {
        var parts = [entry.backend, String(format: "%.1f s", entry.seconds)]
        if let cost = entry.costUSD { parts.append(String(format: "$%.4f", cost)) }
        else if entry.tokens > 0 { parts.append(String(format: "%.1fk tokens", Double(entry.tokens) / 1000)) }
        if let attempts = entry.attempts, attempts > 1 { parts.append("fixed on try \(attempts)") }
        return parts.joined(separator: " · ")
    }
}
