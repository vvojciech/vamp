import SwiftUI
import VampCore

/// Everything about the selected layer, editable by hand. Changes play as soon as the code runs.
struct InspectorView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let id = app.selectedLayerID, let layer = app.song.layers.first(where: { $0.id == id }) {
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
    @Environment(AppModel.self) private var app
    let layer: Layer

    private var error: String? {
        if case let .failure(e)? = app.analysis[layer.id] { e.message } else { nil }
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
                Button(role: .destructive) { app.update { $0.layers.removeAll { $0.id == layer.id } } } label: {
                    Image(systemName: "trash")
                }
                .help("Delete layer")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.muted)

            CodeEditor(text: Binding(
                get: { layer.code },
                set: { code in app.updateLayer(layer.id, coalesce: true) { $0.code = code } }))
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
        }
        app.selectedLayerID = newID
    }
}
