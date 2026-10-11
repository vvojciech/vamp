import SwiftUI
import VampCore

/// Everything about the selected layer or section, editable by hand. Changes play as soon as the code runs.
struct InspectorView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        if app.inspectsSection, let id = app.selectedSectionID, let section = app.song.section(id) {
            SectionInspector(section: section)
                .id(section.id)
        } else if let id = app.selectedLayerID, let layer = app.song.layers.first(where: { $0.id == id }) {
            LayerInspector(layer: layer)
                .id(layer.id)
        } else {
            Text("Select a layer to see its code.")
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.panel)
        }
    }
}

private struct LayerInspector: View {
    @EnvironmentObject private var app: AppModel
    let layer: Layer
    /// Nil edits the code used everywhere. A section id edits that section's own version.
    @State private var scope: String?

    private var error: String? {
        if case let .failure(e)? = app.analysis[layer.id] { e.message } else { nil }
    }

    /// Sections where this layer plays, which are the places it can have its own code.
    private var playingSections: [Section] { app.song.sections.filter { $0.layerIDs.contains(layer.id) } }

    private var codeBinding: Binding<String> {
        Binding(
            get: { scope.flatMap { app.song.section($0)?.variations[layer.id] } ?? layer.code },
            set: { code in
                if let scope {
                    app.updateSection(scope, coalesce: true) { $0.variations[layer.id] = code }
                } else {
                    app.updateLayer(layer.id, coalesce: true) { $0.code = code }
                }
            })
    }

    var body: some View {
        let tint = Theme.color(for: layer.role)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 9, height: 9)
                TextField("Layer name", text: Binding(
                    get: { layer.name },
                    set: { name in app.updateLayer(layer.id, coalesce: true) { $0.name = name } }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: 220)
                Picker("Role", selection: Binding(
                    get: { layer.role },
                    set: { role in app.updateLayer(layer.id) { $0.role = role } })) {
                    ForEach(LayerRole.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("\(Int(layer.gain * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate layer")
                Button(role: .destructive) { app.update { $0.removeLayer(layer.id) } } label: {
                    Image(systemName: "trash")
                }
                .help("Delete layer")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.muted)

            if !playingSections.isEmpty { ScopeBar(layer: layer, sections: playingSections, scope: $scope) }

            CodeEditor(text: codeBinding)
                .id(scope ?? "everywhere")
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.window))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(error == nil ? Theme.line : Theme.danger.opacity(0.6)))

            HStack(spacing: 6) {
                if let error {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    Text(error).foregroundStyle(Theme.danger.opacity(0.95)).lineLimit(2).textSelection(.enabled)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x3FD8C7))
                    Text("Runs. Edits play straight away.").foregroundStyle(Theme.muted)
                }
                Spacer()
                Link("Strudel reference", destination: URL(string: "https://strudel.cc/learn/")!)
                    .foregroundStyle(Theme.faint)
            }
            .font(.system(size: 11.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
    }

    private func duplicate() {
        var newID = ""
        app.update { song in
            guard let index = song.index(of: layer.id) else { return }
            var copy = layer
            copy.name = "\(layer.name) copy"
            copy.id = song.uniqueID(for: copy.name)
            copy.solo = false
            newID = copy.id
            song.layers.insert(copy, at: index + 1)
            for i in song.sections.indices where song.sections[i].layerIDs.contains(layer.id) {
                song.sections[i].layerIDs.append(copy.id)
                song.sections[i].variations[copy.id] = song.sections[i].variations[layer.id]
            }
        }
        app.selectedLayerID = newID
    }
}

/// Chooses which version of the code the editor shows: everywhere, or one section's own.
private struct ScopeBar: View {
    @EnvironmentObject private var app: AppModel
    let layer: Layer
    let sections: [Section]
    @Binding var scope: String?

    var body: some View {
        HStack(spacing: 6) {
            chip("Everywhere", isOn: scope == nil, marked: false) { scope = nil }
            ForEach(sections) { section in
                chip(section.name, isOn: scope == section.id, marked: section.variations[layer.id] != nil) {
                    // The first edit in a section starts from the code used everywhere.
                    if section.variations[layer.id] == nil {
                        app.updateSection(section.id) { $0.variations[layer.id] = layer.code }
                    }
                    scope = section.id
                }
            }
            Spacer()
            if let scope, app.song.section(scope)?.variations[layer.id] != nil {
                Button("Use the everywhere code here") {
                    app.updateSection(scope) { $0.variations[layer.id] = nil }
                    self.scope = nil
                }
                .buttonStyle(.borderless).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, marked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if marked { Image(systemName: "wand.and.stars").font(.system(size: 9)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 10).frame(height: 24)
            .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.muted)
            .background(Capsule().fill(isOn ? Theme.sectionTint : Theme.raised))
        }
        .buttonStyle(.plain)
        .help(marked ? "\(title) has its own code for this layer" : "Edit this layer for \(title) only")
    }
}
