import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Passing lists between installations")
struct ListExchangeTests {
    private func list(id: String, title: String, sort: ListSort = .updated) -> SavedList {
        SavedList(
            id: id, title: title, query: "is:pr is:open author:@me",
            content: .pullRequests, symbolName: "flame", sort: sort, includeDrafts: true
        )
    }

    @Test("A document survives the round trip with everything a list carries")
    func roundTrip() throws {
        let original = [list(id: "a", title: "Mine", sort: .created), list(id: "b", title: "Theirs")]
        let read = try ListExchange.decode(try ListExchange.encode(original))
        #expect(read == original)
        #expect(read.first?.includeDrafts == true)
        #expect(read.first?.symbolName == "flame")
    }

    /// The file lands in a chat message or a repository, where reordered
    /// keys would read as a change.
    @Test("The written file is readable and stably ordered")
    func readable() throws {
        let text = String(decoding: try ListExchange.encode([list(id: "a", title: "Mine")]), as: UTF8.self)
        #expect(text.contains("\n"))
        #expect(text.range(of: "\"content\"")!.lowerBound < text.range(of: "\"query\"")!.lowerBound)
    }

    @Test("What cannot be read is refused by name")
    func refusals() {
        #expect(throws: ListExchange.ExchangeError.unreadable) {
            try ListExchange.decode(Data("not json at all".utf8))
        }
        #expect(throws: ListExchange.ExchangeError.empty) {
            try ListExchange.decode(Data(#"{"format":1,"lists":[]}"#.utf8))
        }
        #expect(throws: ListExchange.ExchangeError.tooNew(9)) {
            try ListExchange.decode(Data(#"{"format":9,"lists":[{"id":"a","title":"t","query":"q","content":"issues"}]}"#.utf8))
        }
    }

    /// The three lists the app seeds carry the same ids on every machine, so
    /// a colleague's file lands on your own unless the question is asked.
    @Test("The plan says what is replaced and what is new")
    func plan() {
        let existing = [list(id: "reviews", title: "My review queue"), list(id: "mine", title: "Mine")]
        let incoming = [list(id: "reviews", title: "Reviews Requested"), list(id: "ready", title: "Ready to merge")]

        let plan = ListExchange.plan(importing: incoming, into: existing)
        #expect(plan.replacing.map(\.existingTitle) == ["My review queue"])
        #expect(plan.replacing.map(\.incoming.title) == ["Reviews Requested"])
        #expect(plan.adding.map(\.title) == ["Ready to merge"])
        #expect(plan.count == 2)
    }

    @Test("Nothing incoming is a plan that does nothing")
    func emptyPlan() {
        #expect(ListExchange.plan(importing: [], into: [list(id: "a", title: "Mine")]).isEmpty)
    }

    /// A replaced list keeps its place in the sidebar: an import should not
    /// silently reshuffle the order someone arranged.
    @Test("Replacements keep their place, new ones go to the end")
    func apply() {
        let existing = [
            list(id: "a", title: "First"),
            list(id: "b", title: "Second"),
            list(id: "c", title: "Third"),
        ]
        let incoming = [list(id: "b", title: "Second, rewritten"), list(id: "d", title: "Fourth")]

        let result = ListExchange.apply(incoming, to: existing)
        #expect(result.map(\.title) == ["First", "Second, rewritten", "Third", "Fourth"])
    }

    @Test("Importing your own file back changes nothing")
    func ownFile() throws {
        let existing = [list(id: "a", title: "First"), list(id: "b", title: "Second")]
        let read = try ListExchange.decode(try ListExchange.encode(existing))
        #expect(ListExchange.apply(read, to: existing) == existing)
    }
}
