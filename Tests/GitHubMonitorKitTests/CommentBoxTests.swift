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
