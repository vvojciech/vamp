import SwiftUI
import VampCore

/// The song's sections as blocks along time. Click one to edit it, or loop it while you work.
struct ArrangementBar: View {
    @EnvironmentObject private var app: AppModel
    /// Playhead in view time.
    let position: Double?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Sections").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                if !app.song.sections.isEmpty {
                    Button { app.loopsSection.toggle() } label: {
                        Label("Loop", systemImage: "repeat")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8).frame(height: 22)
                            .foregroundStyle(app.loopsSection ? Color.black.opacity(0.85) : Theme.muted)
                            .background(RoundedRectangle(cornerRadius: 6).fill(app.loopsSection ? Theme.sectionTint : Theme.raised))
                    }
                    .buttonStyle(.plain)
                    .disabled(app.selectedSectionID == nil)
                    .help(app.selectedSectionID == nil ? "Select a section to loop it" : "Play and show only the selected section")
                }
                AddSectionMenu()
            }
            .padding(.horizontal, 10)
            .frame(width: SheetView.headerWidth)

            if app.song.sections.isEmpty {
                Text("One loop. Add a section to build an intro, a bridge or an outro, or ask the agent.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            } else {
                Blocks(songPosition: position.map { Double(app.window.start) + $0 })
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }
}

private struct Blocks: View {
    @EnvironmentObject private var app: AppModel
    let songPosition: Double?

    var body: some View {
        GeometryReader { geo in
            let total = Double(app.song.totalBars ?? 1)
            let gap: CGFloat = 3
            let usable = geo.size.width - gap * CGFloat(max(app.song.sections.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(Array(app.song.sections.enumerated()), id: \.element.id) { index, section in
                    Block(section: section, index: index, width: usable * CGFloat(Double(section.bars) / total))
                }
            }
            .overlay(alignment: .topLeading) {
                if let songPosition {
                    Capsule().fill(Theme.playhead).frame(width: 2, height: 46)
                        .shadow(color: .white.opacity(0.7), radius: 3)
                        .offset(x: geo.size.width * CGFloat(songPosition / total) - 1, y: -3)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 40)
    }
}

private struct Block: View {
    @EnvironmentObject private var app: AppModel
    let section: Section
    let index: Int
    let width: CGFloat

    private var isSelected: Bool { app.selectedSectionID == section.id }
    private var isDimmed: Bool { app.loopsSection && !isSelected }

    var body: some View {
        let tint = Theme.sectionColor(index)
        VStack(alignment: .leading, spacing: 1) {
            Text(section.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Text("\(section.bars) bars").font(.system(size: 10.5)).foregroundStyle(Theme.text.opacity(0.6)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(width: max(width, 8), height: 40, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(isSelected ? 0.95 : 0.55)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isSelected ? Color.white.opacity(0.75) : .clear, lineWidth: 1.5))
        .opacity(isDimmed ? 0.4 : 1)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            app.selectedSectionID = section.id
            app.inspectsSection = true
        }
        .contextMenu {
            Button("Loop this section") {
                app.selectedSectionID = section.id
                app.loopsSection = true
            }
            Button("Delete section", role: .destructive) {
                app.update { $0.sections.removeAll { $0.id == section.id } }
            }
        }
        .help("\(section.name), \(section.bars) bars, \(section.layerIDs.count) layers")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Adds a section from a common song part. An intro goes first, everything else last.
struct AddSectionMenu: View {
    @EnvironmentObject private var app: AppModel
    private let parts: [(String, Int)] = [("Intro", 4), ("Verse", 8), ("Chorus", 8), ("Bridge", 8),
                                          ("Breakdown", 4), ("Build-up", 4), ("Drop", 8), ("Outro", 4)]

    var body: some View {
        Menu {
            ForEach(parts, id: \.0) { name, bars in
                Button(name) { add(name, bars) }
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add a section")
    }

    private func add(_ name: String, _ bars: Int) {
        var newID = ""
        app.update { song in
            newID = song.addSection(name: name, bars: bars, layerIDs: nil, position: name == "Intro" ? 0 : nil)
        }
        app.selectedSectionID = newID
        app.inspectsSection = true
    }
}
