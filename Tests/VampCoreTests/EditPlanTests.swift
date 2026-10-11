import Foundation
import Testing
@testable import VampCore

private let base = Song(title: "Groove", bpm: 110, layers: [
    Layer(id: "drums", name: "Drums", role: .drums, code: "s(\"bd*4\")"),
    Layer(id: "bass", name: "Bass", role: .bass, code: "note(\"c2\")"),
])

@Suite struct EditPlanTests {
    @Test func decodesNullableFieldsFromModelJSON() throws {
        let json = """
        {"summary":"Added hats","edits":[{"op":"add_layer","layer_id":null,"name":"Hats","role":"drums","code":"s(\\"hh*8\\")","gain":0.5,"bpm":null,"title":null}]}
        """
        let plan = try JSONDecoder().decode(EditPlan.self, from: Data(json.utf8))
        #expect(plan.summary == "Added hats")
        #expect(plan.edits.first?.op == .addLayer)
        #expect(plan.edits.first?.gain == 0.5)
    }

    @Test func addLayerAppendsWithUniqueID() throws {
        var song = base
        let change = try EditPlan.Edit(op: .addLayer, name: "Bass", role: .bass, code: "note(\"e2\")").apply(to: &song)
        #expect(song.layers.last?.id == "bass-2")
        #expect(song.layers.last?.gain == 0.8)
        #expect(change == .added("bass-2"))
    }

    @Test func updateLayerChangesOnlyGivenFields() throws {
        var song = base
        let change = try EditPlan.Edit(op: .updateLayer, layerID: "bass", code: "note(\"g1\")", gain: 0.6).apply(to: &song)
        #expect(song.layers[1].code == "note(\"g1\")")
        #expect(song.layers[1].gain == 0.6)
        #expect(song.layers[1].name == "Bass")
        #expect(change == .changed("bass"))
    }

    @Test func removeLayerDeletesIt() throws {
        var song = base
        #expect(try EditPlan.Edit(op: .removeLayer, layerID: "drums").apply(to: &song) == .removed("drums"))
        #expect(song.layers.map(\.id) == ["bass"])
    }

    @Test func tempoIsClamped() throws {
        var song = base
        _ = try EditPlan.Edit(op: .setTempo, bpm: 999).apply(to: &song)
        #expect(song.bpm == 220)
    }

    @Test func unknownLayerIsAnError() {
        var song = base
        #expect(throws: EditError.self) { try EditPlan.Edit(op: .updateLayer, layerID: "nope", code: "x").apply(to: &song) }
    }

    @Test func addWithoutCodeIsAnError() {
        var song = base
        #expect(throws: EditError.self) { try EditPlan.Edit(op: .addLayer, name: "X").apply(to: &song) }
    }

    @Test func thePlanComesFirstSoTheEditsFollowFromIt() throws {
        let schema = EditPlan.jsonSchema
        let plan = try #require(schema.range(of: "\"plan\""))
        let edits = try #require(schema.range(of: "\"edits\":{"))
        #expect(plan.lowerBound < edits.lowerBound)
        let object = try JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any]
        #expect((object?["required"] as? [String])?.contains("plan") == true)
    }

    @Test func aPlanDecodesWithTheEdits() throws {
        let json = #"{"plan":"C minor, 100 BPM, 8 sections.","summary":"s","edits":[]}"#
        #expect(try JSONDecoder().decode(EditPlan.self, from: Data(json.utf8)).plan == "C minor, 100 BPM, 8 sections.")
    }

    @Test func schemaIsValidJSONWithStrictShape() throws {
        let object = try JSONSerialization.jsonObject(with: Data(EditPlan.jsonSchema.utf8)) as? [String: Any]
        #expect(object?["additionalProperties"] as? Bool == false)
        let edit = ((object?["properties"] as? [String: Any])?["edits"] as? [String: Any])?["items"] as? [String: Any]
        let props = (edit?["properties"] as? [String: Any])?.keys.sorted()
        #expect(props == (edit?["required"] as? [String])?.sorted())
    }
}
