import Foundation
import Testing
@testable import Vamp

@Suite struct PersistenceTests {
    /// A session saved by an earlier version: it has the removed `scorecard` and `rounds`
    /// fields, and an entry without `attempts`.
    private let oldSession = """
    {"song":{"title":"Old","bpm":100,"layers":[]},
     "scorecard":{"aspects":[]},"scorecardJudged":true,
     "chat":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","request":"add hats","backend":"Claude Haiku",
              "state":{"done":{}},"summary":"Added hats","changes":[],"tokens":5000,"seconds":12,
              "songBefore":{"title":"Old","bpm":100,"layers":[]},"rounds":[]}]}
    """

    @Test func anOlderSessionStillLoads() throws {
        let snapshot = try #require(Persistence.decode(Data(oldSession.utf8)))
        #expect(snapshot.song.title == "Old")
        #expect(snapshot.chat.first?.summary == "Added hats")
        #expect(snapshot.chat.first?.attempts == nil)
    }

    @Test func aDamagedFileLoadsNothingInsteadOfCrashing() {
        #expect(Persistence.decode(Data("{not json".utf8)) == nil)
    }
}
