import Testing
@testable import GitHubMonitorKit

/// What a notification row says a mention actually said.
@Suite("A remark in one line")
struct CommentDigestTests {
    @Test("The first thing worth reading, flattened onto one line")
    func plain() {
        #expect(CommentDigest.firstLine(of: "Wie sollen die Bestandsdaten umgezogen werden?")
            == "Wie sollen die Bestandsdaten umgezogen werden?")
        #expect(CommentDigest.firstLine(of: "\n\n  Second try  \n\nand more")
            == "Second try")
    }

    /// Pull request templates open with one, and a row showing it would
    /// say nothing at all.
    @Test("An HTML comment is stepped over, however many lines it spans")
    func htmlComments() {
        #expect(CommentDigest.firstLine(of: "<!-- a note to the author -->\nThe real line")
            == "The real line")
        #expect(
            CommentDigest.firstLine(of: "<!--\nWhen you're not merging\ninto main\n-->\nHere it is")
                == "Here it is"
        )
        #expect(CommentDigest.firstLine(of: "<!-- one --> after it") == "after it")
    }

    @Test("Markers come off, words stay")
    func markers() {
        #expect(CommentDigest.firstLine(of: "## Pre-merge checklist") == "Pre-merge checklist")
        #expect(CommentDigest.firstLine(of: "- [ ] MigrationChangeLog entry added")
            == "MigrationChangeLog entry added")
        #expect(CommentDigest.firstLine(of: "**Important** and `code`") == "Important and code")
    }

    /// A quote is what somebody is answering, not what they said; a rule,
    /// a fence, a table row and a lone image say nothing in a list.
    @Test("What says nothing in a row is skipped")
    func skipped() {
        #expect(CommentDigest.firstLine(of: "> you wrote this\n\nand this is my answer")
            == "and this is my answer")
        #expect(CommentDigest.firstLine(of: "---\n\nAfter the rule") == "After the rule")
        #expect(CommentDigest.firstLine(of: "```swift\nlet a = 1\n```\nAfter the code")
            == "let a = 1")
        #expect(CommentDigest.firstLine(of: "![shot](x.png)\nThe words") == "The words")
        #expect(CommentDigest.firstLine(of: "") == "")
        #expect(CommentDigest.firstLine(of: "<!-- only a comment -->") == "")
    }

    @Test("A long remark stops on a word")
    func shortened() {
        let long = String(repeating: "word ", count: 80)
        let line = CommentDigest.firstLine(of: long, limit: 40)
        #expect(line.count <= 41)
        #expect(line.hasSuffix("\u{2026}"))
        #expect(!line.contains("  "))
    }
}

/// Whether the line a row shows really is the one that named you.
@Suite("Naming somebody in a body")
struct MentionTextTests {
    @Test("The name has to end where the name ends")
    func boundaries() {
        #expect(IssueComment.mentions("sidler", in: "cc @sidler please look"))
        #expect(IssueComment.mentions("sidler", in: "@sidler"))
        #expect(IssueComment.mentions("SIDLER", in: "@sidler, thoughts?"))
        // `@sid` must not match `@sidler`.
        #expect(!IssueComment.mentions("sid", in: "@sidler"))
        #expect(!IssueComment.mentions("sidler", in: "@sidler-bot ran it"))
        #expect(!IssueComment.mentions("sidler", in: "no names here"))
        #expect(!IssueComment.mentions("", in: "@ anybody"))
    }
}
