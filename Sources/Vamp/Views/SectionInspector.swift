import SwiftUI
import VampCore

/// Name, length, order and layers of one section.
struct SectionInspector: View {
    @EnvironmentObject private var app: AppModel
    let section: Section

    private var index: Int { app.song.sections.firstIndex { $0.id == section.id } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.sectionColor(index)).frame(width: 12, height: 12)
                TextField("Section name", text: Binding(
                    get: { section.name },
                    set: { name in app.updateSection(section.id, coalesce: true) { $0.name = name } }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: 220)
                Stepper(value: Binding(
                    get: { section.bars },
                    set: { bars in app.updateSection(section.id, coalesce: true) { $0.bars = bars } }),
                    in: Section.barRange) {
                    Text("\(section.bars) bars").font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .fixedSize()
                Spacer()
                Button { move(by: -1) } label: { Image(systemName: "arrow.left") }
                    .disabled(index == 0).help("Move earlier")
                Button { move(by: 1) } label: { Image(systemName: "arrow.right") }
                    .disabled(index == app.song.sections.count - 1).help("Move later")
                Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate section")
                Button(role: .destructive) { app.update { $0.sections.removeAll { $0.id == section.id } } } label: {
                    Image(systemName: "trash")
                }
                .help("Delete section")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.muted)

            Text("Layers that play in this section").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.muted)
            LayerToggles(section: section)

            if !section.variations.isEmpty {
                let names = app.song.layers.filter { section.variations[$0.id] != nil }.map(\.name)
                Label("Own code here: \(names.joined(separator: ", ")). Select the layer to edit it.", systemImage: "wand.and.stars")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel)
    }

    private func move(by offset: Int) {
        app.update { $0.moveSection(at: index, to: index + offset) }
    }

    private func duplicate() {
        var newID = ""
        app.update { song in
            var copy = section
            copy.id = song.uniqueSectionID(for: section.name)
            newID = copy.id
            song.sections.insert(copy, at: index + 1)
        }
        app.selectedSectionID = newID
    }
}

private struct LayerToggles: View {
    @EnvironmentObject private var app: AppModel
    let section: Section

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(app.song.layers) { layer in
                let isOn = section.layerIDs.contains(layer.id)
                let tint = Theme.color(for: layer.role)
                Button {
                    app.updateSection(section.id) { s in
                        if isOn { s.layerIDs.removeAll { $0 == layer.id } } else { s.layerIDs = app.song.knownLayers(s.layerIDs + [layer.id]) }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? tint : Theme.faint)
                        Text(layer.name).lineLimit(1).foregroundStyle(isOn ? Theme.text : Theme.muted)
                        if section.variations[layer.id] != nil {
                            Image(systemName: "wand.and.stars").font(.system(size: 9)).foregroundStyle(Theme.muted)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? tint.opacity(0.14) : Theme.raised.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
