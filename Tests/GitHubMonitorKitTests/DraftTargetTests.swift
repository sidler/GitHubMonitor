import Foundation
import Testing

@testable import GitHubMonitorKit

/// The box a remark is written in: which file and line it belongs to, and
/// what happens to it when the diff turns to another file.
@Suite("The box a remark is written in")
@MainActor
struct DraftTargetTests {
    /// The whole point of the box knowing its file. Reading one file at a
    /// time means turning to the next takes the patch view with it, and
    /// the half-written remark used to go with the view.
    @Test("Turning to another file keeps what has been typed")
    func survivesTurningThePage() {
        let target = DraftTarget()
        target.open(path: "src/Session.php", line: 42, side: .new)
        target.text = "This lock is held too long"

        // The next file draws itself and asks whether the box is its own.
        #expect(target.isOpen(path: "src/Filter.php", line: 42, side: .new) == false)
        #expect(target.text == "This lock is held too long")

        // And back again.
        #expect(target.isOpen(path: "src/Session.php", line: 42, side: .new))
    }

    /// Line 42 of one file is not line 42 of the next.
    @Test("The same line in another file is another place")
    func lineAloneIsNotEnough() {
        let target = DraftTarget()
        target.open(path: "a.swift", line: 7, side: .new)

        #expect(target.isOpen(path: "a.swift", line: 7, side: .new))
        #expect(target.isOpen(path: "b.swift", line: 7, side: .new) == false)
        #expect(target.isOpen(path: "a.swift", line: 8, side: .new) == false)
        #expect(target.isOpen(path: "a.swift", line: 7, side: .old) == false)
    }

    @Test("A reply takes its file from the conversation it answers")
    func replyKnowsItsFile() {
        let target = DraftTarget()
        let thread = ReviewThread(
            id: "T1",
            path: "src/Session.php",
            line: 118,
            side: .new,
            isResolved: false,
            isOutdated: false,
            comments: []
        )

        target.open(reply: thread)

        #expect(target.path == "src/Session.php")
        #expect(target.isReplying(to: "T1"))
        // A reply hangs off its conversation, not off a bare line, so no
        // line of the file claims the box.
        #expect(target.isOpen(path: "src/Session.php", line: 118, side: .new) == false)
    }

    @Test("Sending or cancelling leaves no file behind")
    func shutting() {
        let target = DraftTarget()
        target.open(path: "a.swift", line: 7, side: .new, text: "half a thought")
        target.previewing = true

        target.shut()

        #expect(target.path == "")
        #expect(target.line == nil)
        #expect(target.text == "")
        #expect(target.previewing == false)
        #expect(target.isOpen(path: "a.swift", line: 7, side: .new) == false)
    }

    /// Opening the box somewhere else is a different remark, not a
    /// continuation of the last one.
    @Test("Opening the box elsewhere starts afresh")
    func movingTheBox() {
        let target = DraftTarget()
        target.open(path: "a.swift", line: 7, side: .new, text: "about a")

        target.open(path: "b.swift", line: 9, side: .old)

        #expect(target.isOpen(path: "b.swift", line: 9, side: .old))
        #expect(target.isOpen(path: "a.swift", line: 7, side: .new) == false)
        #expect(target.text == "")
    }
}
