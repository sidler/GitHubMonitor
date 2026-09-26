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
