import SwiftUI
import VampCore

/// Seven aspect scores, live from the notes, with a button that polishes the song to 9+.
struct ScorecardView: View {
    @Environment(AppModel.self) private var app
    @State private var expanded: AspectName?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Score").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                if let card = app.scorecard {
                    Text(String(format: "%.1f", card.overall))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Self.color(card.overall))
                    Text(app.scorecardJudged ? "measured and judged" : "measured")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                        .help(app.scorecardJudged
                              ? "The lower of the measured score and a second model's review, per aspect."
                              : "Measured from the notes. Polish adds a review by a second model.")
                }
                Spacer()
                PolishButton()
            }
            if let card = app.scorecard {
                ForEach(card.aspects, id: \.name) { aspect in
                    AspectRow(aspect: aspect, expanded: expanded == aspect.name) {
                        withAnimation(.easeOut(duration: 0.15)) { expanded = expanded == aspect.name ? nil : aspect.name }
                    }
                }
            } else {
                Text("Scores appear once the engine has read the song.").font(.callout).foregroundStyle(Theme.faint)
            }
        }
        .padding(16)
    }

    static func color(_ score: Double) -> Color {
        score >= 9 ? Color(hex: 0x3FD8C7) : score >= 7 ? Color(hex: 0xFFC15E) : Theme.danger
    }
}

private struct AspectRow: View {
    let aspect: Aspect
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Text(aspect.name.label).font(.system(size: 12)).foregroundStyle(Theme.text.opacity(0.85))
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.raised)
                            Capsule().fill(ScorecardView.color(aspect.score))
                                .frame(width: max(4, geo.size.width * aspect.score / 10))
                        }
                    }
                    .frame(height: 6)
                    Text(String(format: "%.1f", aspect.score))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ScorecardView.color(aspect.score))
                        .frame(width: 30, alignment: .trailing)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(aspect.notes.isEmpty ? .clear : Theme.faint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(aspect.notes.isEmpty)
            .accessibilityLabel("\(aspect.name.label), \(String(format: "%.1f", aspect.score)) out of 10")

            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(aspect.notes, id: \.self) { note in
                        Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                .padding(.leading, 102)
            }
        }
    }
}

private struct PolishButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.isPolishing {
            Button { app.cancelAgent() } label: {
                Label("Stop", systemImage: "stop.fill").font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(.borderless).foregroundStyle(Theme.muted)
        } else {
            Button { app.polish() } label: {
                Label("Polish to 9+", systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10).frame(height: 24)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(app.isAgentWorking || app.song.layers.isEmpty)
            .opacity(app.isAgentWorking ? 0.4 : 1)
            .help("Review the song, revise it with the critique, and repeat until every aspect scores 9 or more. Uses \(app.backend.displayName(model: app.backend.composerModel)) to write and \(app.backend.displayName(model: app.backend.judgeModel)) to judge.")
        }
    }
}
