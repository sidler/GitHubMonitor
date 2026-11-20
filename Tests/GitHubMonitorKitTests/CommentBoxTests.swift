import AppKit
import Testing

@testable import GitHubMonitorKit

/// The box a remark is written in, and the one thing it must not do to
/// somebody in the middle of typing.
@Suite("Comment box")
@MainActor
struct CommentBoxTests {
    /// A backtick on a German keyboard is an accent that waits for the
    /// next key. While it waits it is marked text: in the view, not
    /// committed, and not reported as a change -- so the binding still
    /// holds the string without it. The caret moved, which was enough to
    /// bring the view back round to being handed that older string, and
    /// assigning it put the pending backtick out. No backtick could be
    /// typed at all.
    @Test("A pending dead key survives being handed the text again")
    func markedTextSurvives() {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.string = "abc"
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.setMarkedText(
            "`",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 3, length: 0)
        )
        #expect(view.hasMarkedText())

        let took = CommentTextView.hand("abc", selection: nil, to: view)

        #expect(took == false)
        #expect(view.hasMarkedText())
        #expect(view.string == "abc`")
    }

    @Test("With nothing pending the view takes the text and the selection")
    func handsOver() {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.string = "old"

        let took = CommentTextView.hand(
            "a **word**", selection: NSRange(location: 4, length: 4), to: view
        )

        #expect(took)
        #expect(view.string == "a **word**")
        #expect(view.selectedRange() == NSRange(location: 4, length: 4))
    }

    /// The model and the view can disagree for a moment, and a selection
    /// past the end of the string is a crash rather than a wrong caret.
    @Test("A selection past the end of the text is brought back inside it")
    func boundedSelection() {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.string = "ab"

        CommentTextView.hand("ab", selection: NSRange(location: 99, length: 5), to: view)

        #expect(view.selectedRange() == NSRange(location: 2, length: 0))
    }
}

/// The box grows with what is written in it rather than scrolling inside
/// a fixed height, which is what hid the first lines of anything longer
/// than two.
@Suite("Comment box height")
@MainActor
struct CommentBoxHeightTests {
    private func height(_ text: String, width: CGFloat = 400) -> CGFloat {
        CommentTextView.height(of: text, width: width, fontSize: 13)
    }

    @Test("More lines want more room")
    func growsWithLines() {
        #expect(height("one\ntwo\nthree") > height("one"))
    }

    @Test("A narrower box wraps the same prose taller")
    func growsWhenNarrower() {
        let long = String(repeating: "a word ", count: 40)
        #expect(height(long, width: 200) > height(long, width: 600))
    }

    @Test("An empty box still has a line to write on")
    func emptyHasALine() {
        #expect(height("") > 0)
    }

    /// The one assumption in the measurement: that a layout of our own
    /// pads a line the way the text view does. Wrong, and every box
    /// would be a line out.
    @Test("The measurement agrees with the box that draws it")
    func agreesWithTheRealBox() {
        for text in ["one", "one\ntwo\nthree", String(repeating: "a word ", count: 40)] {
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000))
            view.isRichText = false
            view.textContainerInset = CommentTextView.inset
            view.font = NSFont.systemFont(ofSize: 13)
            view.isVerticallyResizable = true
            view.textContainer?.widthTracksTextView = true
            view.string = text
            guard let layout = view.layoutManager, let container = view.textContainer else {
                Issue.record("no layout")
                return
            }
            layout.ensureLayout(for: container)
            let drawn =
                ceil(layout.usedRect(for: container).height) + 2 * CommentTextView.inset.height
            #expect(abs(drawn - height(text)) < 1)
        }
    }
}
