import Foundation
import Testing
@testable import VampCore

@Suite struct BackendOutputTests {
    @Test func claudeCLIReadsStructuredOutputAndCost() throws {
        let raw = """
        {"type":"result","is_error":false,"result":"{}","structured_output":{"summary":"ok","edits":[]},"total_cost_usd":0.0038,"usage":{"input_tokens":1172,"output_tokens":535}}
        """
        let reply = try BackendOutput.claudeCLI(Data(raw.utf8))
        #expect(reply.costUSD == 0.0038)
        #expect(reply.inputTokens == 1172)
        #expect(try JSONDecoder().decode(EditPlan.self, from: reply.json).summary == "ok")
    }

    @Test func claudeCLIErrorIsSurfaced() {
        let raw = #"{"type":"result","is_error":true,"result":"Not logged in"}"#
        #expect(throws: BackendError.message("Not logged in")) { try BackendOutput.claudeCLI(Data(raw.utf8)) }
    }

    @Test func codexReadsLastMessageAndUsage() throws {
        let events = """
        {"type":"turn.started"}
        {"type":"turn.completed","usage":{"input_tokens":24382,"cached_input_tokens":0,"output_tokens":32}}
        """
        let reply = try BackendOutput.codex(lastMessage: #"{"summary":"x","edits":[]}"#, events: events)
        #expect(reply.inputTokens == 24382)
        #expect(reply.outputTokens == 32)
        #expect(reply.costUSD == nil)
    }

    @Test func codexFailedTurnIsSurfaced() {
        let events = #"{"type":"turn.failed","error":{"message":"usage limit reached"}}"#
        #expect(throws: BackendError.message("usage limit reached")) { try BackendOutput.codex(lastMessage: "", events: events) }
    }

    @Test func anthropicAPIReadsTextAndPricesUsage() throws {
        let raw = """
        {"content":[{"type":"text","text":"{\\"summary\\":\\"s\\",\\"edits\\":[]}"}],"stop_reason":"end_turn","usage":{"input_tokens":1000000,"output_tokens":100000}}
        """
        let reply = try BackendOutput.anthropicAPI(Data(raw.utf8), model: .haiku)
        #expect(reply.costUSD == 1.5)
        #expect(String(decoding: reply.json, as: UTF8.self).contains("summary"))
    }

    @Test func anthropicAPIErrorIsSurfaced() {
        let raw = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        #expect(throws: BackendError.message("invalid x-api-key")) { try BackendOutput.anthropicAPI(Data(raw.utf8), model: .haiku) }
    }
}
