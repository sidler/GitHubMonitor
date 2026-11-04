import Foundation
import Testing

@testable import GitHubMonitorKit

/// What the formatting buttons above the box write, and where they leave
/// the selection afterwards.
@Suite("Markdown buttons")
struct MarkdownEditingTests {
    private func apply(
        _ action: MarkdownAction, _ text: String, _ location: Int, _ length: Int
    ) -> MarkdownEditing.Written {
        MarkdownEditing.applying(
            action, to: text, selection: NSRange(location: location, length: length)
        )
    }

    @Test("Bold puts asterisks round what is chosen and keeps it chosen")
    func bold() {
        let written = apply(.bold, "a word here", 2, 4)
        #expect(written.text == "a **word** here")
        #expect(written.selection == NSRange(location: 4, length: 4))
    }

    @Test("Bold a second time takes the asterisks off again")
    func unbold() {
        let written = apply(.bold, "a **word** here", 2, 8)
        #expect(written.text == "a word here")
        #expect(written.selection == NSRange(location: 2, length: 4))
    }

    /// The word selected from inside the asterisks already there, which
    /// is how a selection usually ends up after a double click.
    @Test("Bold undoes asterisks that are round the selection")
    func unboldFromInside() {
        let written = apply(.bold, "a **word** here", 4, 4)
        #expect(written.text == "a word here")
        #expect(written.selection == NSRange(location: 2, length: 4))
    }

    @Test("Bold with nothing chosen leaves the caret between the asterisks")
    func boldEmpty() {
        let written = apply(.bold, "say ", 4, 0)
        #expect(written.text == "say ****")
        #expect(written.selection == NSRange(location: 6, length: 0))
    }

    @Test("Italic uses one underscore, strikethrough two tildes")
    func others() {
        #expect(apply(.italic, "word", 0, 4).text == "_word_")
        #expect(apply(.strikethrough, "word", 0, 4).text == "~~word~~")
    }

    @Test("Code on one line is backticks")
    func inlineCode() {
        let written = apply(.code, "see Sources/App.swift now", 4, 17)
        #expect(written.text == "see `Sources/App.swift` now")
        #expect(written.selection == NSRange(location: 5, length: 17))
    }

    /// One backtick cannot hold a snippet that has one in it, and
    /// markdown's answer is to use more of them than the content does.
    @Test("Code round a snippet that has a backtick uses two")
    func longerFence() {
        let written = apply(.code, "a `b` c", 0, 7)
        #expect(written.text == "``a `b` c``")
    }

    @Test("Code round a snippet that starts with a backtick is padded")
    func paddedFence() {
        #expect(apply(.code, "`x", 0, 2).text == "`` `x ``")
    }

    @Test("Code a second time takes the backticks off")
    func uncode() {
        let written = apply(.code, "see `path` now", 4, 6)
        #expect(written.text == "see path now")
        #expect(written.selection == NSRange(location: 4, length: 4))
    }

    @Test("Code over more than one line is a fenced block")
    func fenced() {
        let written = apply(.code, "let a = 1\nlet b = 2", 0, 19)
        #expect(written.text == "```\nlet a = 1\nlet b = 2\n```")
        #expect(written.selection == NSRange(location: 4, length: 19))
    }

    /// A fence in the middle of a sentence is three backticks in the
    /// middle of a sentence.
    @Test("A fence that would not start a line gets one")
    func fenceOnItsOwnLine() {
        let written = apply(.code, "look: a\nb", 6, 3)
        #expect(written.text == "look: \n```\na\nb\n```")
    }

    @Test("Code a second time unfences a block")
    func unfence() {
        let written = apply(.code, "```\na\nb\n```", 0, 11)
        #expect(written.text == "a\nb")
    }

    @Test("A link round words leaves the caret where the address goes")
    func link() {
        let written = apply(.link, "see the docs", 8, 4)
        #expect(written.text == "see the [docs]()")
        #expect(written.selection == NSRange(location: 15, length: 0))
    }

    @Test("A link round an address leaves the caret where the words go")
    func linkFromAddress() {
        let written = apply(.link, "https://example.com", 0, 19)
        #expect(written.text == "[](https://example.com)")
        #expect(written.selection == NSRange(location: 1, length: 0))
    }

    @Test("A bullet goes in front of every line the selection touches")
    func bullets() {
        let written = apply(.bullet, "one\ntwo\nthree", 0, 13)
        #expect(written.text == "- one\n- two\n- three")
        #expect(written.selection == NSRange(location: 0, length: 19))
    }

    @Test("A bullet a second time takes the marks off again")
    func unbullet() {
        #expect(apply(.bullet, "- one\n- two", 0, 11).text == "one\ntwo")
    }

    /// Half a list marked means the button is being used to mark the
    /// rest, not to undo what is there.
    @Test("A half-marked block is marked the rest of the way")
    func halfMarked() {
        #expect(apply(.bullet, "- one\ntwo", 0, 9).text == "- one\n- two")
    }

    @Test("A numbered list counts up")
    func numbers() {
        #expect(apply(.number, "one\ntwo\nthree", 0, 13).text == "1. one\n2. two\n3. three")
    }

    @Test("A numbered list a second time loses its numbers")
    func unnumber() {
        #expect(apply(.number, "1. one\n2. two", 0, 13).text == "one\ntwo")
    }

    @Test("A task list writes empty boxes")
    func tasks() {
        #expect(apply(.task, "one\ntwo", 0, 7).text == "- [ ] one\n- [ ] two")
    }

    /// Taking "- " off a task would leave the box behind on a line that
    /// is no longer a list item.
    @Test("A bullet does not half-undo a task")
    func taskIsNotABullet() {
        #expect(apply(.bullet, "- [ ] one", 0, 9).text == "- - [ ] one")
    }

    @Test("A quote marks the line the caret is on and moves the caret with it")
    func quoteFromCaret() {
        let written = apply(.quote, "one\ntwo", 5, 0)
        #expect(written.text == "one\n> two")
        #expect(written.selection == NSRange(location: 7, length: 0))
    }

    /// A mark on an empty line is a bullet with nothing after it.
    @Test("A blank line inside a block stays blank")
    func blankLines() {
        #expect(apply(.bullet, "one\n\ntwo", 0, 8).text == "- one\n\n- two")
    }

    @Test("A selection reaching past the end is brought back inside it")
    func clamped() {
        #expect(apply(.bold, "ab", 0, 99).text == "**ab**")
        #expect(apply(.bold, "ab", 99, 0).text == "ab****")
    }
}
