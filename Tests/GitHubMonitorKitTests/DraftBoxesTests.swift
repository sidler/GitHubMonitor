import Foundation
import Testing

@testable import GitHubMonitorKit

/// The boxes remarks are written in: where they belong, and what keeps
/// them alive while the diff moves on.
@Suite("The boxes remarks are written in")
@MainActor
struct DraftBoxesTests {
    private func thread(_ id: String, path: String, line: Int) -> ReviewThread {
        ReviewThread(
            id: id, path: path, line: line, side: .new,
            isResolved: false, isOutdated: false, comments: []
        )
    }

    /// The whole point of keeping these in the review. Reading one file
    /// at a time means turning to the next takes the patch view with it,
    /// and the half-written remark used to go with the view.
    @Test("Turning to another file keeps what has been typed")
    func survivesTurningThePage() {
        let boxes = DraftBoxes()
        let box = boxes.open(path: "src/Session.php", line: 42, side: .new)
        box.text = "This lock is held too long"

        // The next file draws itself and finds nothing of its own.
        #expect(boxes.isOpen(path: "src/Filter.php", line: 42, side: .new) == false)

        // And back again, with the same box and the same words in it.
        let found = boxes.box(at: DraftPlace(path: "src/Session.php", line: 42, side: .new))
        #expect(found === box)
        #expect(found?.text == "This lock is held too long")
    }

    /// A thought about the third file does not wait for the remark begun
    /// on the first to be finished.
    @Test("Several remarks can be half-written at once")
    func several() {
        let boxes = DraftBoxes()
        boxes.open(path: "a.swift", line: 7, side: .new).text = "about a"
        boxes.open(path: "b.swift", line: 9, side: .old).text = "about b"
        boxes.open(reply: thread("T1", path: "c.swift", line: 3)).text = "an answer"

        #expect(boxes.count == 3)
        #expect(boxes.box(at: DraftPlace(path: "a.swift", line: 7, side: .new))?.text == "about a")
        #expect(boxes.box(at: DraftPlace(path: "b.swift", line: 9, side: .old))?.text == "about b")
        #expect(boxes.isReplying(to: "T1"))
    }

    /// Line 42 of one file is not line 42 of the next.
    @Test("The same line in another file is another box")
    func lineAloneIsNotEnough() {
        let boxes = DraftBoxes()
        boxes.open(path: "a.swift", line: 7, side: .new)

        #expect(boxes.isOpen(path: "a.swift", line: 7, side: .new))
        #expect(boxes.isOpen(path: "b.swift", line: 7, side: .new) == false)
        #expect(boxes.isOpen(path: "a.swift", line: 8, side: .new) == false)
        #expect(boxes.isOpen(path: "a.swift", line: 7, side: .old) == false)
    }

    @Test("A reply hangs off its conversation, not off a line")
    func replyKnowsItsThread() {
        let boxes = DraftBoxes()
        let conversation = thread("T1", path: "src/Session.php", line: 118)

        boxes.open(reply: conversation)

        #expect(boxes.isReplying(to: "T1"))
        #expect(boxes.isReplying(to: "T2") == false)
        // The line it hangs on belongs to the conversation, so no row of
        // the file claims the box for itself.
        #expect(boxes.isOpen(path: "src/Session.php", line: 118, side: .new) == false)
    }

    @Test("Sending or cancelling takes only that box away")
    func shutting() {
        let boxes = DraftBoxes()
        boxes.open(path: "a.swift", line: 7, side: .new).text = "about a"
        boxes.open(path: "b.swift", line: 9, side: .new).text = "about b"

        boxes.shut(DraftPlace(path: "a.swift", line: 7, side: .new))

        #expect(boxes.isOpen(path: "a.swift", line: 7, side: .new) == false)
        #expect(boxes.box(at: DraftPlace(path: "b.swift", line: 9, side: .new))?.text == "about b")
        #expect(boxes.count == 1)
    }

    /// The plus in the gutter is easy to hit twice, and the second press
    /// must not wipe what was typed between them.
    @Test("Opening a box that is already open keeps what is in it")
    func openingTwice() {
        let boxes = DraftBoxes()
        let first = boxes.open(path: "a.swift", line: 7, side: .new)
        first.text = "half a thought"

        let again = boxes.open(path: "a.swift", line: 7, side: .new)

        #expect(again === first)
        #expect(again.text == "half a thought")
        #expect(boxes.count == 1)
    }

    /// Reworking a remark that is already in the draft is a different
    /// matter: it puts that remark's words into the box on purpose.
    @Test("Editing a saved remark fills the box with it")
    func editing() {
        let boxes = DraftBoxes()
        boxes.open(path: "a.swift", line: 7, side: .new).text = "stale"
        let id = UUID()

        let box = boxes.open(
            path: "a.swift", line: 7, side: .new, text: "the saved words", editing: id
        )

        #expect(box.text == "the saved words")
        #expect(box.editing == id)
        #expect(boxes.count == 1)
    }

    /// An empty box is nothing anybody would miss, so nobody is asked
    /// about it on the way out.
    @Test("Only the boxes with words in them count as unfinished")
    func unfinished() {
        let boxes = DraftBoxes()
        boxes.open(path: "a.swift", line: 7, side: .new)
        boxes.open(path: "b.swift", line: 9, side: .new).text = "   \n  "
        boxes.open(path: "c.swift", line: 1, side: .new).text = "a real thought"

        #expect(boxes.count == 3)
        #expect(boxes.unfinished.count == 1)
        #expect(boxes.unfinished.first?.text == "a real thought")
    }

    /// These become remarks, and remarks that come out in a different
    /// order each time are remarks nobody trusts.
    @Test("Unfinished remarks come out in the order they sit in the diff")
    func unfinishedOrder() {
        let boxes = DraftBoxes()
        boxes.open(path: "b.swift", line: 4, side: .new).text = "third"
        boxes.open(path: "a.swift", line: 9, side: .new).text = "second"
        boxes.open(path: "a.swift", line: 2, side: .new).text = "first"

        #expect(boxes.unfinished.map(\.text) == ["first", "second", "third"])
    }
}

/// What the windows know about half-written remarks, which is what the
/// questions on the way out are asked about.
@Suite("Half-written remarks across reviews")
@MainActor
struct UnfinishedAcrossReviewsTests {
    @Test("A review with nothing written in it is not counted")
    func onlyReviewsWithWords() {
        let windows = ReviewWindows()
        windows.boxes(for: "PR_1").open(path: "a.swift", line: 1, side: .new).text = "say this"
        // Opened and left empty, which is nothing anybody would miss.
        windows.boxes(for: "PR_2").open(path: "b.swift", line: 1, side: .new)

        let unfinished = windows.unfinishedByReview

        #expect(unfinished.keys.sorted() == ["PR_1"])
        #expect(unfinished["PR_1"]?.count == 1)
    }

    @Test("Several reviews are counted together")
    func acrossReviews() {
        let windows = ReviewWindows()
        windows.boxes(for: "PR_1").open(path: "a.swift", line: 1, side: .new).text = "one"
        windows.boxes(for: "PR_1").open(path: "a.swift", line: 2, side: .new).text = "two"
        windows.boxes(for: "PR_2").open(path: "b.swift", line: 1, side: .new).text = "three"

        let unfinished = windows.unfinishedByReview

        #expect(unfinished.values.reduce(0) { $0 + $1.count } == 3)
        #expect(unfinished.keys.sorted() == ["PR_1", "PR_2"])
    }

    /// The same set of boxes every time it is asked for, or the editor
    /// loses what is being typed into it on the next pass.
    @Test("A review is handed the same boxes every time")
    func sameBoxes() {
        let windows = ReviewWindows()
        let first = windows.boxes(for: "PR_1")
        first.open(path: "a.swift", line: 1, side: .new).text = "half a thought"

        #expect(windows.boxes(for: "PR_1") === first)
        #expect(windows.boxes(for: "PR_1").unfinished.first?.text == "half a thought")
    }
}
