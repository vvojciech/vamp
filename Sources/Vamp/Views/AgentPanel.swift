import SwiftUI
import VampCore

/// The conversation with the agent: what was asked, what changed, what it cost.
struct AgentPanel: View {
    @Environment(AppModel.self) private var app

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
    @Environment(AppModel.self) private var app
    private let ideas = ["Make it darker and slower", "Add a shuffling hi-hat groove", "Turn the bass into a rolling 16th line",
                         "Add a dreamy pad under everything", "Strip it back to drums and bass", "Make the arp jump octaves"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe a change in plain words. The agent edits only the layers it needs to, and you can undo any change.")
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
    @Environment(AppModel.self) private var app
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
                    ChangeChips(changes: entry.changes, song: app.song)
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
    let changes: [EditPlan.Change]
    let song: Song

    var body: some View {
        if !changes.isEmpty {
            FlowRow(items: changes.map(describe))
        }
    }

    private func describe(_ change: EditPlan.Change) -> (String, String, Color) {
        func name(_ id: String) -> String { song.layers.first { $0.id == id }?.name ?? id }
        func tint(_ id: String) -> Color { song.layers.first { $0.id == id }.map { Theme.color(for: $0.role) } ?? Theme.muted }
        switch change {
        case let .added(id): return ("plus", name(id), tint(id))
        case let .changed(id): return ("pencil", name(id), tint(id))
        case let .removed(id): return ("minus", id, Theme.muted)
        case .tempo: return ("metronome", "\(Int(song.bpm)) BPM", Theme.muted)
        case .title: return ("textformat", "Title", Theme.muted)
        }
    }
}

private struct FlowRow: View {
    let items: [(String, String, Color)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            Label(item.1, systemImage: item.0)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(item.2.opacity(0.13)))
        }
    }
}

private struct Footer: View {
    @Environment(AppModel.self) private var app
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
