import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Reading the conversations off a diff")
struct ReviewThreadsQueryTests {
    private func payload(_ nodes: [[String: Any]], next: String? = nil) -> [String: Any] {
        [
            "node": [
                "reviewThreads": [
                    "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any],
                    "nodes": nodes,
                ],
            ],
        ]
    }

    private func node(
        id: String = "t1",
        path: String = "a.swift",
        line: Int? = 12,
        side: String = "RIGHT",
        resolved: Bool = false,
        outdated: Bool = false,
        comments: [[String: Any]] = [["id": "c1", "body": "hm", "author": ["login": "mira"]]]
    ) -> [String: Any] {
        [
            "id": id, "path": path, "line": line as Any, "diffSide": side,
            "isResolved": resolved, "isOutdated": outdated,
            "comments": ["nodes": comments],
        ]
    }

    @Test("A thread carries its line, its side and its state")
    func thread() throws {
        let page = ReviewThreadsQuery.page(from: payload([node()]))
        let thread = try #require(page.threads.first)
        #expect(thread.path == "a.swift")
        #expect(thread.line == 12)
        #expect(thread.side == .new)
        #expect(thread.comments.count == 1)
        #expect(thread.isPlaceable)
    }

    /// `LEFT` is the file as it was: a remark on a line that went away.
    @Test("The side says which file the line is in")
    func sides() {
        let left = ReviewThreadsQuery.page(from: payload([node(side: "LEFT")])).threads
        #expect(left.first?.side == .old)
        // Anything else is the new file, which is nearly all of them.
        #expect(ReviewThread.Side(apiValue: nil) == .new)
    }

    /// GitHub gives no line once the code has been rewritten. The diff
    /// cannot place it, and `originalLine` belongs to a file that is no
    /// longer on screen.
    @Test("A thread with no line knows it cannot be placed")
    func unplaceable() {
        let threads = ReviewThreadsQuery.page(
            from: payload([node(line: nil, outdated: true)])
        ).threads
        #expect(threads.first?.isPlaceable == false)
        #expect(threads.first?.isOutdated == true)
    }

    /// A thread whose every comment was deleted is a box with nothing in
    /// it, and the diff is better off without the gap.
    @Test("A thread with no readable comments is dropped")
    func empty() {
        #expect(ReviewThreadsQuery.page(from: payload([node(comments: [])])).threads.isEmpty)
        // A comment with no id cannot be read, which leaves the thread bare.
        #expect(ReviewThreadsQuery.page(
            from: payload([node(comments: [["body": "orphan"]])])
        ).threads.isEmpty)
    }

    @Test("A page says where to carry on, and the last one does not")
    func paging() {
        #expect(ReviewThreadsQuery.page(from: payload([node()], next: "cursor")).cursor == "cursor")
        #expect(ReviewThreadsQuery.page(from: payload([node()])).cursor == nil)
    }

    @Test("An answer that is not a pull request is empty, not a crash")
    func notAPullRequest() {
        #expect(ReviewThreadsQuery.page(from: ["node": [:]]).threads.isEmpty)
        #expect(ReviewThreadsQuery.page(from: [:]).threads.isEmpty)
    }

    @Test("The query asks for the state as well as the text")
    func document() {
        for field in ["isResolved", "isOutdated", "diffSide", "line", "rateLimit"] {
            #expect(ReviewThreadsQuery.document.contains(field))
        }
    }
}

@Suite("Putting the conversations where they belong")
struct ReviewThreadPlacementTests {
    private func thread(
        _ id: String,
        path: String = "a.swift",
        line: Int?,
        side: ReviewThread.Side = .new,
        resolved: Bool = false,
        outdated: Bool = false
    ) -> ReviewThread {
        ReviewThread(
            id: id, path: path, line: line, side: side,
            isResolved: resolved, isOutdated: outdated,
            comments: [IssueComment(
                id: "c-\(id)", author: "mira", avatarURL: nil, createdAt: .now, body: "hm"
            )]
        )
    }

    /// Open threads first: those are the ones asking for something. Within
    /// each group by line, so they run down the file the way the reader does.
    @Test("Open threads come before resolved ones, and both run down the file")
    func order() {
        let placed = ReviewThreadPlacement.placed([
            thread("a", line: 30),
            thread("b", line: 10, resolved: true),
            thread("c", line: 20),
        ], in: "a.swift")
        #expect(placed.map(\.id) == ["c", "a", "b"])
    }

    @Test("Only this file's threads, and only the ones the patch can hold")
    func filtering() {
        let threads = [
            thread("mine", line: 5),
            thread("other", path: "b.swift", line: 5),
            thread("stale", line: nil, outdated: true),
        ]
        #expect(ReviewThreadPlacement.placed(threads, in: "a.swift").map(\.id) == ["mine"])
        #expect(ReviewThreadPlacement.unplaceable(threads, in: "a.swift").map(\.id) == ["stale"])
    }

    /// An outdated thread that GitHub still gives a line for is gathered
    /// too: the line it names is in a version of the file nobody is looking
    /// at, so placing it would put the remark beside unrelated code.
    @Test("An outdated thread is gathered even when it has a line")
    func outdatedWithLine() {
        let threads = [thread("stale", line: 9, outdated: true)]
        #expect(ReviewThreadPlacement.placed(threads, in: "a.swift").isEmpty)
        #expect(ReviewThreadPlacement.unplaceable(threads, in: "a.swift").count == 1)
    }

    /// Counted by conversation, not by comment: five replies arguing one
    /// point are one thing to deal with, and "5" beside a file name would
    /// send somebody looking for five of them. Both numbers are kept, and
    /// the tooltip says which is which.
    @Test("A file's badge counts conversations, and knows how many comments they hold")
    func counts() {
        let long = ReviewThread(
            id: "argument", path: "a.swift", line: 1, side: .new,
            isResolved: false, isOutdated: false,
            comments: (0..<5).map {
                IssueComment(
                    id: "c\($0)", author: "mira", avatarURL: nil, createdAt: .now, body: "no"
                )
            }
        )
        let counts = ReviewThreadPlacement.openCounts([long, thread("other", line: 2)])
        #expect(counts["a.swift"] == .init(conversations: 2, total: 2, comments: 6))
        #expect(counts["a.swift"]?.text == "2")
        #expect(counts["a.swift"]?.label == "2 open conversations, 6 comments")
    }

    /// Resolved is settled, so it is not open -- but the diff still draws
    /// it, folded to a line. A list that left it out entirely said 1 beside
    /// a file showing two conversations, which is the mismatch this pair of
    /// numbers exists to close.
    @Test("Resolved conversations are not open, but they are still there")
    func resolvedCountsTowardsTheTotal() {
        let counts = ReviewThreadPlacement.openCounts([
            thread("done", line: 1, resolved: true),
            thread("open", line: 2),
        ])
        #expect(counts["a.swift"]?.conversations == 1)
        #expect(counts["a.swift"]?.total == 2)
        #expect(counts["a.swift"]?.text == "1/2")
        #expect(counts["a.swift"]?.label == "1 open conversation of 2, 1 comment")

        // A file whose conversations are all settled says so rather than
        // saying nothing: the diff draws them, and the list has to agree.
        let settled = ReviewThreadPlacement.openCounts(
            [thread("done", line: 1, resolved: true)]
        )
        #expect(settled["a.swift"]?.text == "0/1")
    }

    /// GitHub cannot place them any more, so they sit at the file's header
    /// rather than in its patch -- but unresolved is unresolved, and a file
    /// whose entry said nothing is a file nobody opens again.
    @Test("An outdated conversation still counts as open")
    func outdatedCounts() {
        let counts = ReviewThreadPlacement.openCounts([
            thread("stale", line: nil, outdated: true)
        ])
        #expect(counts["a.swift"]?.conversations == 1)
    }

    @Test("One conversation reads as one, not as 1 conversations")
    func singular() {
        #expect(
            ReviewThreadPlacement.OpenComments(conversations: 1, total: 1, comments: 1).label
                == "1 open conversation, 1 comment"
        )
    }

    /// Matched on the file's line numbers, not on a position in the patch:
    /// GitHub counts in the file, the patch counts in itself.
    @Test("A thread hangs on the line its side numbers")
    func matching() {
        let threads = [thread("new", line: 20), thread("old", line: 11, side: .old)]
        let place = DiffLineNumber(old: 11, new: 20)
        #expect(ReviewThreadPlacement.on(place, from: threads).map(\.id).sorted() == ["new", "old"])
        // The same numbers on the wrong sides catch nothing.
        #expect(ReviewThreadPlacement.on(
            DiffLineNumber(old: 20, new: 11), from: threads
        ).isEmpty)
    }
}

@Suite("Cutting the patch around the conversations")
struct ReviewThreadAnchorTests {
    private func thread(_ id: String, line: Int) -> ReviewThread {
        ReviewThread(
            id: id, path: "a.swift", line: line, side: .new,
            isResolved: false, isOutdated: false,
            comments: [IssueComment(
                id: "c-\(id)", author: "mira", avatarURL: nil, createdAt: .now, body: "hm"
            )]
        )
    }

    /// The patch counts its own lines; GitHub counts the file's. A thread
    /// on new line 21 belongs to whichever patch line carries that number.
    @Test("A thread lands on the patch line that carries its number")
    func unified() {
        let patch = "@@ -10,2 +20,2 @@\n context\n+added"
        let anchors = ReviewThreadAnchors.unified(patch: patch, threads: [thread("t", line: 21)])
        #expect(anchors.keys.sorted() == [2])
    }

    /// Two columns pair lines up, so a row can carry a number from each
    /// file and a thread may hang off either side of it.
    @Test("In two columns a thread hangs off whichever side names its line")
    func sideBySide() {
        let rows = DiffSideBySide.rows(
            of: "@@ -1,1 +1,1 @@\n-    $id = $row['id'];\n+    $id = $row['login'];"
        )
        let onNew = ReviewThreadAnchors.sideBySide(rows: rows, threads: [thread("t", line: 1)])
        #expect(onNew.keys.sorted() == [1])
    }
}


/// A conversation the list counts has to be drawn somewhere.
@MainActor
@Suite("Conversations the patch cannot hold")
struct StrandedThreadTests {
    private func thread(
        _ id: String, line: Int?, side: ReviewThread.Side = .new, outdated: Bool = false
    ) -> ReviewThread {
        ReviewThread(
            id: id, path: "a.swift", line: line, side: side,
            isResolved: false, isOutdated: outdated,
            comments: [
                IssueComment(
                    id: "c-\(id)", author: "mira", avatarURL: nil,
                    createdAt: .now, body: "look here"
                ),
            ]
        )
    }

    /// Two hunks, so the file has lines 10-11 and 40-41 and nothing else.
    private let patch = """
    @@ -10,2 +10,2 @@ class Thing
    -was
    +is
    @@ -40,2 +40,2 @@ class Thing
    -also was
    +also is
    """

    @Test("A conversation on a line the patch carries is drawn in it")
    func inside() {
        // Line 40 of the new file, not 41: the second hunk's removal
        // belongs to the old file only, so the new side does not advance.
        let threads = [thread("a", line: 10), thread("b", line: 40)]
        let placed = ReviewThreadPlacement.placed(threads, in: "a.swift", patch: patch)
        #expect(placed.map(\.id) == ["a", "b"])
        #expect(ReviewThreadPlacement.stranded(threads, in: "a.swift", patch: patch).isEmpty)
    }

    /// A review of a large file arrives with the hunks GitHub chose to
    /// send. A remark on a line outside them has no row to hang on, and
    /// handed to the view it was passed over in silence -- counted in the
    /// list and drawn nowhere.
    @Test("A conversation on a line the patch does not carry is not lost")
    func outside() {
        let threads = [thread("far", line: 900)]
        #expect(ReviewThreadPlacement.placed(threads, in: "a.swift", patch: patch).isEmpty)
        #expect(
            ReviewThreadPlacement.stranded(threads, in: "a.swift", patch: patch).map(\.id)
                == ["far"]
        )
    }

    @Test("Outdated and unplaced ones are stranded as they always were")
    func outdatedAndUnplaced() {
        let threads = [thread("stale", line: 10, outdated: true), thread("nowhere", line: nil)]
        #expect(ReviewThreadPlacement.placed(threads, in: "a.swift", patch: patch).isEmpty)
        #expect(
            Set(ReviewThreadPlacement.stranded(threads, in: "a.swift", patch: patch).map(\.id))
                == ["stale", "nowhere"]
        )
    }

    /// The two sides are counted separately: line 10 of the old file and
    /// line 10 of the new one are different lines.
    @Test("A side the patch does not carry is not a match")
    func sides() {
        let onOld = [thread("old", line: 10, side: .old)]
        #expect(ReviewThreadPlacement.placed(onOld, in: "a.swift", patch: patch).map(\.id)
            == ["old"])

        let beyondOld = [thread("old", line: 900, side: .old)]
        #expect(ReviewThreadPlacement.placed(beyondOld, in: "a.swift", patch: patch).isEmpty)
    }

    /// Every conversation is either drawn in the patch or gathered at the
    /// header. Nothing counted may fall between the two.
    @Test("Placed and stranded together are all of them")
    func nothingFallsThrough() {
        let threads = [
            thread("a", line: 10), thread("far", line: 900),
            thread("stale", line: 11, outdated: true), thread("nowhere", line: nil),
        ]
        let placed = ReviewThreadPlacement.placed(threads, in: "a.swift", patch: patch)
        let stranded = ReviewThreadPlacement.stranded(threads, in: "a.swift", patch: patch)

        #expect(placed.count + stranded.count == threads.count)
        #expect(Set(placed.map(\.id)).isDisjoint(with: Set(stranded.map(\.id))))
    }
}
