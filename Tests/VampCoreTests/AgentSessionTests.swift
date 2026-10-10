import Foundation
import Testing
@testable import VampCore

private let song = Song(title: "G", bpm: 100, layers: [Layer(id: "drums", name: "Drums", role: .drums, code: "s(\"bd*4\")")])

private func reply(_ json: String, cost: Double? = 0.001) -> BackendReply {
    BackendReply(json: Data(json.utf8), costUSD: cost, inputTokens: 10, outputTokens: 5)
}

private actor Script {
    var replies: [BackendReply]
    var prompts: [String] = []
    init(_ replies: [BackendReply]) { self.replies = replies }
    func next(_ prompt: String) -> BackendReply { prompts.append(prompt); return replies.removeFirst() }
}

@Suite struct AgentSessionTests {
    @Test func appliesPlanWhenCodeIsValid() async throws {
        let script = Script([reply(#"{"summary":"Hats in","edits":[{"op":"add_layer","layer_id":null,"name":"Hats","role":"drums","code":"s(\"hh*8\")","gain":null,"bpm":null,"title":null}]}"#)])
        let result = try await AgentSession.run(
            request: "add hats", song: song, history: [],
            ask: { _, user in await script.next(user) },
            validate: { _ in [:] })
        #expect(result.song.layers.map(\.id) == ["drums", "hats"])
        #expect(result.summary == "Hats in")
        #expect(result.changes == [.added("hats")])
        #expect(result.attempts == 1)
    }

    @Test func repairsOnceWhenCodeFails() async throws {
        let bad = #"{"summary":"v1","edits":[{"op":"update_layer","layer_id":"drums","name":null,"role":null,"code":"s(\"bd*4\"","gain":null,"bpm":null,"title":null}]}"#
        let good = #"{"summary":"v2","edits":[{"op":"update_layer","layer_id":"drums","name":null,"role":null,"code":"s(\"bd*2\")","gain":null,"bpm":null,"title":null}]}"#
        let script = Script([reply(bad), reply(good)])
        let result = try await AgentSession.run(
            request: "fewer kicks", song: song, history: [],
            ask: { _, user in await script.next(user) },
            validate: { s in s.layers[0].code.hasSuffix(")") ? [:] : ["drums": "Unexpected end of input"] })
        #expect(result.song.layers[0].code == "s(\"bd*2\")")
        #expect(result.attempts == 2)
        #expect(result.costUSD == 0.002)
        let repairPrompt = await script.prompts[1]
        #expect(repairPrompt.contains("Unexpected end of input"))
    }

    @Test func givesUpAfterTwoFailedAttemptsAndKeepsSong() async {
        let bad = #"{"summary":"v","edits":[{"op":"update_layer","layer_id":"drums","name":null,"role":null,"code":"oops(","gain":null,"bpm":null,"title":null}]}"#
        let script = Script([reply(bad), reply(bad)])
        await #expect(throws: AgentError.self) {
            _ = try await AgentSession.run(
                request: "x", song: song, history: [],
                ask: { _, user in await script.next(user) },
                validate: { _ in ["drums": "SyntaxError"] })
        }
    }

    @Test func promptCarriesSongAndHistory() {
        let prompt = AgentPrompt.user(request: "darker", song: song, history: [.init(request: "add drums", summary: "Added drums")])
        #expect(prompt.contains("\"id\" : \"drums\""))
        #expect(prompt.contains("add drums"))
        #expect(prompt.hasSuffix("darker"))
    }
}
