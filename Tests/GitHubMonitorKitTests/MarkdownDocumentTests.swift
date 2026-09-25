import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Markdown blocks")
struct MarkdownDocumentTests {
    @Test("A plain comment is one paragraph")
    func paragraph() {
        #expect(MarkdownDocument.blocks(from: "Looks good to me.") == [.paragraph("Looks good to me.")])
    }

    /// GitHub renders a single newline as a line break, so a paragraph keeps
    /// the shape its author gave it rather than being reflowed.
    @Test("Line breaks inside a paragraph survive")
    func lineBreaks() {
        #expect(
            MarkdownDocument.blocks(from: "first\nsecond") == [.paragraph("first\nsecond")]
        )
    }

    @Test("A blank line starts a new paragraph")
    func paragraphs() {
        #expect(
            MarkdownDocument.blocks(from: "one\n\ntwo") == [.paragraph("one"), .paragraph("two")]
        )
    }

    @Test("Headings are read with their level")
    func headings() {
        #expect(MarkdownDocument.blocks(from: "## Release Notes") == [.heading(level: 2, text: "Release Notes")])
        #expect(MarkdownDocument.blocks(from: "#### Configuration") == [.heading(level: 4, text: "Configuration")])
    }

    /// A hash without a space is part of the text -- "#35442" is how every
    /// pull request in this app is referred to.
    @Test("A pull request number is not a heading")
    func hashIsNotAlwaysAHeading() {
        #expect(MarkdownDocument.blocks(from: "#35442 is ready") == [.paragraph("#35442 is ready")])
    }

    @Test("Bullets are collected into one list")
    func bullets() {
        let blocks = MarkdownDocument.blocks(from: "- one\n- two\n* three")
        #expect(blocks == [.bullets(["one", "two", "three"])])
    }

    @Test("Numbered items keep their text, not their numbers")
    func numbered() {
        #expect(MarkdownDocument.blocks(from: "1. first\n2) second") == [.numbered(["first", "second"])])
    }

    @Test("Quotes are one block, without their markers")
    func quotes() {
        #expect(MarkdownDocument.blocks(from: "> a\n> b") == [.quote("a\nb")])
    }

    /// Code is the one place where wrapping and reflowing change meaning, so
    /// it is kept exactly as written.
    @Test("Fenced code is kept verbatim")
    func code() {
        let source = "```swift\nlet a = 1\n\n  let b = 2\n```"
        #expect(MarkdownDocument.blocks(from: source) == [.code("let a = 1\n\n  let b = 2")])
    }

    @Test("An unclosed fence still ends the document")
    func unclosedFence() {
        #expect(MarkdownDocument.blocks(from: "```\nx") == [.code("x")])
    }

    /// The word after the fence is what tells the highlighter which language
    /// it is looking at; it used to be read and thrown away.
    @Test("A fence hands its language to the block")
    func fenceLanguage() {
        #expect(MarkdownDocument.blocks(from: "```php\n$a = 1;\n```") == [
            .code("$a = 1;", language: .php),
        ])
        #expect(MarkdownDocument.blocks(from: "```\nplain\n```") == [.code("plain")])
        // A fence naming something nobody here writes is still a code block.
        #expect(MarkdownDocument.blocks(from: "```cobol\nSTOP RUN.\n```") == [
            .code("STOP RUN."),
        ])
    }

    @Test("Rules are their own block")
    func rules() {
        #expect(MarkdownDocument.blocks(from: "a\n\n---\n\nb") == [.paragraph("a"), .rule, .paragraph("b")])
    }

    @Test("A table keeps its header and drops the alignment row")
    func table() {
        let source = """
        | Package | Change |
        |---|---|
        | prettier | `3.9.7` -> `3.9.8` |
        """
        #expect(
            MarkdownDocument.blocks(from: source) == [
                .table(header: ["Package", "Change"], rows: [["prettier", "`3.9.7` -> `3.9.8`"]])
            ]
        )
    }

    /// GitHub renders a table whose rows have no outer pipes, and people
    /// write them that way; this one used to come out as a paragraph.
    @Test("A table without its outer pipes is still a table")
    func bareTable() {
        let source = """
        Package | Change
        ------- | ------
        prettier | `3.9.8`
        eslint | `9.2.0`
        """
        #expect(
            MarkdownDocument.blocks(from: source) == [
                .table(
                    header: ["Package", "Change"],
                    rows: [["prettier", "`3.9.8`"], ["eslint", "`9.2.0`"]]
                )
            ]
        )
    }

    /// The rule underneath is what makes a header a header. Without it a
    /// line with a pipe in it is a sentence, and stays one.
    @Test("A sentence with a pipe in it is not a table")
    func pipeInProse() {
        let source = "Run `ls | wc -l` first.\nThen read the output."
        #expect(MarkdownDocument.blocks(from: source) == [
            .paragraph("Run `ls | wc -l` first.\nThen read the output.")
        ])
    }

    /// A bare table ends where the pipes end, and what follows is prose
    /// again rather than another row.
    @Test("A bare table stops at the first line without a pipe")
    func bareTableEnds() {
        let source = """
        Name | Value
        --- | ---
        a | 1

        Some words after it.
        """
        #expect(
            MarkdownDocument.blocks(from: source) == [
                .table(header: ["Name", "Value"], rows: [["a", "1"]]),
                .paragraph("Some words after it."),
            ]
        )
    }

    @Test("Alignment markers do not make a row of content")
    func alignmentRow() {
        #expect(MarkdownDocument.isAlignmentRow([":---", "---:", ":-:"]))
        #expect(!MarkdownDocument.isAlignmentRow(["prettier", "3.9.8"]))
    }

    /// Bots wrap their release notes in `<details>`; the summary is the only
    /// label the section below it has, so it becomes its heading.
    @Test("A details summary becomes a heading and its wrapper disappears")
    func details() {
        let source = "<details>\n<summary>prettier/prettier</summary>\n\ntext\n</details>"
        #expect(
            MarkdownDocument.blocks(from: source) == [
                .heading(level: 4, text: "prettier/prettier"),
                .paragraph("text"),
            ]
        )
    }

    @Test("Comments and badges are dropped")
    func noise() {
        let source = "<!-- renovate-debug: eyJ -->\n![badge](https://example.com/a.svg) done"
        #expect(MarkdownDocument.blocks(from: source) == [.paragraph(" done")])
    }

    @Test("A line break tag becomes a line break")
    func breakTag() {
        #expect(MarkdownDocument.blocks(from: "a<br>b") == [.paragraph("a\nb")])
    }

    @Test("An empty body has no blocks")
    func empty() {
        #expect(MarkdownDocument.blocks(from: "").isEmpty)
        #expect(MarkdownDocument.blocks(from: "\n\n  \n").isEmpty)
    }

    /// The renovate body from the report that prompted this: a table, a
    /// rule, headings and a details wrapper, in one comment.
    @Test("A bot's release notes come out as structure, not as source")
    func realWorld() {
        let source = """
        This PR contains the following updates:

        | Package | Change | Age |
        |---|---|---|
        | [prettier](https://prettier.io) | [`3.9.7` -> `3.9.8`](https://example.com) | ![age](https://badge) |

        ---

        ### Release Notes

        <details>
        <summary>prettier/prettier (prettier)</summary>

        ### [`v3.9.8`](https://example.com)

        [Compare Source](https://example.com)

        </details>

        ---

        ### Configuration
        """
        let blocks = MarkdownDocument.blocks(from: source)

        #expect(blocks.first == .paragraph("This PR contains the following updates:"))
        #expect(blocks.contains(.heading(level: 3, text: "Release Notes")))
        #expect(blocks.contains(.heading(level: 4, text: "prettier/prettier (prettier)")))
        #expect(blocks.contains(.rule))
        #expect(blocks.contains(.heading(level: 3, text: "Configuration")))

        let tables = blocks.compactMap { block -> (header: [String], rows: [[String]])? in
            if case .table(let header, let rows) = block { return (header, rows) }
            return nil
        }
        let table = try? #require(tables.first)
        #expect(table?.header == ["Package", "Change", "Age"])
        #expect(table?.rows.count == 1)
        // The badge is gone, but its column is still there and still empty.
        #expect(table?.rows.first?.count == 3)
        #expect(table?.rows.first?.first?.contains("prettier") == true)

        // Nothing should have survived as raw HTML.
        for block in blocks {
            if case .paragraph(let text) = block {
                #expect(!text.contains("<details>"))
                #expect(!text.contains("</details>"))
            }
        }
    }
}
