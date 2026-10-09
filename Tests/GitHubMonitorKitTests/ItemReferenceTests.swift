import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Reading issue numbers out of text")
struct ItemReferenceTests {
    private let repository = "octo/platform"

    private func titles(_ title: String) -> [ItemLink] {
        ItemReferences.inTitle(title, repository: repository)
    }

    private func bodies(_ body: String) -> [ItemLink] {
        ItemReferences.inBody(body, repository: repository)
    }

    /// The house convention: the title opens with the issue it belongs to.
    @Test("A number at the head of a title is a link")
    func titleOpensWithNumber() {
        let links = titles("#35617 fix(gdpr): Only update an existing checklist")
        #expect(links.count == 1)
        #expect(links.first?.kind == .closes)
        #expect(links.first?.reference == ItemReference(repository: repository, number: 35617))
    }

    /// "part 2 of #35700" is a sentence, not a statement about what this
    /// pull request closes.
    @Test("A number further along the title is only a mention")
    func titleMentionsNumber() {
        #expect(titles("Add search previews (part 2 of #35700)").first?.kind == .mentions)
    }

    @Test("A title with no number has no links")
    func titleWithoutNumber() {
        #expect(titles("feat(aufgaben): Extend task glossary").isEmpty)
    }

    @Test("A number written with its repository belongs to that repository")
    func foreignRepository() {
        let links = titles("Follow-up to octo/toolkit#1204")
        #expect(links.first?.reference == ItemReference(repository: "octo/toolkit", number: 1204))
    }

    /// Without this every link to a comment would read as a reference to
    /// whatever number the anchor happened to carry.
    @Test("An anchor inside a URL is not a reference")
    func urlAnchor() {
        #expect(bodies("see https://github.com/a/b/pull/12#issuecomment-4711").isEmpty)
    }

    @Test("A version number is not a reference")
    func versionNumber() {
        #expect(bodies("upgraded to v2#3 of the format").isEmpty)
    }

    /// A number in a log extract is output, not a statement.
    @Test("Code fences are not read")
    func codeIsNotProse() {
        #expect(bodies("```\nWARN job #4711 failed\n```").isEmpty)
    }

    /// A quoted comment was written by somebody else, somewhere else.
    @Test("Quotes are not read")
    func quotesAreNotProse() {
        #expect(bodies("> as we said in #4711").isEmpty)
    }

    @Test("Numbers in prose, headings, bullets and tables are all found")
    func prose() {
        let body = """
        ## Related to #1

        Closes #2 and touches #3.

        - [ ] blocked by #4

        | Issue | Note |
        | --- | --- |
        | #5 | later |
        """
        #expect(bodies(body).map(\.reference.number) == [1, 2, 3, 4, 5])
        #expect(bodies(body).allSatisfy { $0.kind == .mentions })
    }

    @Test("The same number written twice is one reference")
    func repeated() {
        #expect(bodies("#7 again, and #7 once more").count == 1)
    }

    @Test("A body that is a changelog stops at the limit")
    func capped() {
        let many = (1...20).map { "#\($0)" }.joined(separator: " ")
        #expect(bodies(many).count == ItemReferences.limit)
    }
}

@Suite("Joining links from several places")
struct ItemLinkMergeTests {
    private func link(_ number: Int, _ kind: ItemLink.Kind, title: String? = nil) -> ItemLink {
        ItemLink(
            reference: ItemReference(repository: "octo/platform", number: number),
            kind: kind,
            title: title
        )
    }

    /// GitHub's own answer beats a guess at the same number, and keeps the
    /// title that came with it.
    @Test("What GitHub said wins over what was read from text")
    func graphWins() {
        let merged = ItemLink.merge([[link(1, .closes, title: "The issue")], [link(1, .mentions)]])
        #expect(merged.count == 1)
        #expect(merged.first?.kind == .closes)
        #expect(merged.first?.title == "The issue")
    }

    /// A number found first in a sentence and then in the graph is still a
    /// link -- the order the two sources are consulted in must not decide
    /// how strong the answer is.
    @Test("The stronger kind wins whichever came first")
    func strongerWins() {
        let merged = ItemLink.merge([[link(1, .mentions)], [link(1, .closes, title: "The issue")]])
        #expect(merged.first?.kind == .closes)
        #expect(merged.first?.title == "The issue")
    }

    @Test("Links come before mentions")
    func ordering() {
        let merged = ItemLink.merge([[link(9, .mentions), link(2, .closes)]])
        #expect(merged.map(\.reference.number) == [2, 9])
    }
}


/// What a linked pull request's number says about it.
@Suite("Where a link points, and how it is going")
struct LinkedStateTests {
    private func node(_ fields: [String: Any]) -> [String: Any] {
        var entry: [String: Any] = [
            "number": 482,
            "title": "Fix race condition in session handler",
            "url": "https://github.com/octo/server/pull/482",
            "repository": ["nameWithOwner": "octo/server"],
        ]
        entry.merge(fields) { _, new in new }
        return ["links": ["totalCount": 1, "nodes": [entry]]]
    }

    private func state(_ fields: [String: Any]) -> LinkedSummary.State? {
        ItemLinkParser.links(
            from: node(fields), key: "links", fallbackRepository: "octo/server"
        ).links.first?.state
    }

    @Test("GitHub's three answers, and the draft hiding inside one of them")
    func parsed() {
        #expect(state(["state": "MERGED"]) == .merged)
        #expect(state(["state": "CLOSED"]) == .closed)
        #expect(state(["state": "OPEN"]) == .open)
        // A draft is open, but not in the sense somebody waiting on it
        // means.
        #expect(state(["state": "OPEN", "isDraft": true]) == .draft)
        #expect(state(["state": "OPEN", "isDraft": false]) == .open)
    }

    /// Nil rather than a guess: a chip drawn green because nobody said
    /// otherwise would be a lie about something merged last week.
    @Test("A query that did not ask gets no answer")
    func unasked() {
        #expect(state([:]) == nil)
        #expect(state(["state": "SOMETHING_NEW"]) == nil)
    }

    /// Merging two findings about one number must not lose the state, or
    /// a link GitHub described would come out as plain as a guess.
    @Test("Merging keeps what is known")
    func merging() {
        let reference = ItemReference(repository: "octo/server", number: 482)
        let guessed = ItemLink(reference: reference, kind: .mentions)
        let known = ItemLink(
            reference: reference, kind: .closes, title: "Fix it", state: .merged
        )

        #expect(ItemLink.merge([[guessed], [known]]).first?.state == .merged)
        #expect(ItemLink.merge([[known], [guessed]]).first?.state == .merged)
    }

    @Test("Open and merged do not look the same")
    func tints() {
        #expect(LinkedSummary.State.open.tint != LinkedSummary.State.merged.tint)
        #expect(LinkedSummary.State.closed.tint == LinkedSummary.State.notPlanned.tint)
    }
}
