import SwiftUI
import VampCore

/// Starts a new layer from a small template for its role. It plays in every section.
struct AddLayerMenu: View {
    @EnvironmentObject private var app: AppModel

    static let templates: [(LayerRole, String)] = [
        (.drums, "s(\"bd*4, [~ sd]*2, hh*8\")"),
        (.percussion, "s(\"[~ rm]*2, perc(3,8)\").gain(0.7)"),
        (.bass, "note(\"<c2 g1 ab1 bb1>*4\").s(\"sawtooth\").lpf(700).decay(0.2).sustain(0)"),
        (.chords, "chord(\"<Cm7 Ab^7 Fm7 G7>\").voicing().s(\"triangle\").attack(0.05).release(0.6).room(0.4)"),
        (.pad, "chord(\"<Cm9 Fm9>\").voicing().s(\"supersaw\").attack(1).release(2).lpf(900).room(0.7).gain(0.3)"),
        (.lead, "n(\"<0 [2 4] 3 [4 7]>\").scale(\"C4:minor\").s(\"square\").lpf(2000).delay(0.3)"),
        (.arp, "n(\"0 2 4 7 4 2\").fast(2).scale(\"C4:minor\").s(\"triangle\").decay(0.15).sustain(0)"),
        (.fx, "s(\"white\").struct(\"~ ~ ~ x\").hpf(4000).decay(0.4).sustain(0).gain(0.3)"),
    ]

    var body: some View {
        Menu {
            ForEach(Self.templates, id: \.0) { role, code in
                Button { add(role, code) } label: { Label(role.label, systemImage: Theme.symbol(for: role)) }
            }
        } label: {
            Label("Add layer", systemImage: "plus")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.muted)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func add(_ role: LayerRole, _ code: String) {
        var newID = ""
        app.update { song in
            newID = song.uniqueID(for: role.label)
            song.layers.append(Layer(id: newID, name: role.label, role: role, code: code))
            for i in song.sections.indices { song.sections[i].layerIDs.append(newID) }
        }
        app.selectedLayerID = newID
    }
}
