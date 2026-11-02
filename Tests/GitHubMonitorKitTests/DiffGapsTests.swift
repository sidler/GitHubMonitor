import Foundation
import Testing

@testable import GitHubMonitorKit

/// Where a patch is silent, counted in the new file's own numbering.
@Suite("The lines a patch leaves out")
struct DiffGapsTests {
    /// A file of forty lines, changed in two places. GitHub sends three
    /// lines of context either side, so the patch accounts for 8-14 and
    /// 28-34 and says nothing about the rest.
    private let twoHunks = """
        @@ -8,7 +8,7 @@ class Thing
         eight
         nine
         ten
        -old eleven
        +new eleven
         twelve
         thirteen
         fourteen
        @@ -28,7 +28,7 @@ class Thing
         twenty-eight
         twenty-nine
         thirty
        -old thirty-one
        +new thirty-one
         thirty-two
         thirty-three
         thirty-four
        """

    @Test("The head of the file, the middle and the tail")
    func threeGaps() {
        let gaps = DiffGaps.gaps(in: twoHunks, fileLines: 40)
        #expect(gaps.map { $0.first...$0.last } == [1...7, 15...27, 35...40])
    }

    /// A hunk that starts at line one has nothing above it.
    @Test("A patch that opens at the first line has no gap above")
    func noHead() {
        let patch = """
            @@ -1,4 +1,4 @@
            -old one
            +new one
             two
             three
             four
            """
        #expect(DiffGaps.gaps(in: patch, fileLines: 10).map(\.first) == [5])
    }

    /// The tail is only known because the file's length is known. Without
    /// it there is nothing to claim.
    @Test("A patch reaching the last line has no gap below")
    func noTail() {
        let patch = """
            @@ -1,3 +1,3 @@
            -old one
            +new one
             two
             three
            """
        #expect(DiffGaps.gaps(in: patch, fileLines: 3).isEmpty)
    }

    /// Hunks GitHub chose not to join still sit next to each other.
    @Test("Hunks that touch leave nothing between them")
    func adjacent() {
        let patch = """
            @@ -1,2 +1,2 @@
            -old one
            +new one
             two
            @@ -3,2 +3,2 @@
            -old three
            +new three
             four
            """
        #expect(DiffGaps.gaps(in: patch, fileLines: 4).isEmpty)
    }

    /// A removal is not a line of the new file and must not advance the
    /// count, or every gap after a deletion is off by as many lines as
    /// were deleted.
    @Test("Removed lines do not count towards the new file")
    func removalsDoNotCount() {
        let patch = """
            @@ -1,6 +1,3 @@
             one
            -two
            -three
            -four
             five
             six
            """
        // Three lines survive, so the gap starts at four.
        #expect(DiffGaps.gaps(in: patch, fileLines: 9).map { $0.first...$0.last } == [4...9])
    }

    /// GitHub writes this under a file whose last line has no newline. It
    /// is a note, not a line.
    @Test("The no-newline marker is not a line")
    func noNewlineMarker() {
        let patch = """
            @@ -1,2 +1,2 @@
             one
            -old two
            +new two
            \\ No newline at end of file
            """
        #expect(DiffGaps.gaps(in: patch, fileLines: 2).isEmpty)
    }

    /// GitHub's patches do not end in a newline, but nothing says they
    /// may not. Counted as a context line, the empty piece a trailing
    /// newline splits into pushes every gap below it one line late.
    @Test("A trailing newline on the patch changes nothing")
    func trailingNewline() {
        let patch = "@@ -1,2 +1,2 @@\n one\n-old two\n+new two\n"
        #expect(
            DiffGaps.gaps(in: patch, fileLines: 6).map { $0.first...$0.last } == [3...6]
        )
    }

    /// An empty line in the source can arrive as an empty string rather
    /// than a single space, and it is still a line.
    @Test("An empty context line is a line")
    func emptyContextLine() {
        let patch = "@@ -1,4 +1,4 @@\n one\n\n-old three\n+new three\n four"
        #expect(
            DiffGaps.gaps(in: patch, fileLines: 7).map { $0.first...$0.last } == [5...7]
        )
    }

    /// Unchanged lines exist in both files a fixed distance apart, and
    /// that distance is what the gutter needs to fill both its columns.
    @Test("A gap knows how far the old file is from the new one")
    func offset() {
        // Both hunks sit at the same line in both files, so there is no
        // distance between them.
        #expect(DiffGaps.gaps(in: twoHunks, fileLines: 40).allSatisfy { $0.oldOffset == 0 })

        // Three lines went away above the gap, so the old file is three
        // lines ahead of the new one from there on.
        let shrunk = """
            @@ -1,6 +1,3 @@
             one
            -two
            -three
            -four
             five
             six
            """
        #expect(DiffGaps.gaps(in: shrunk, fileLines: 9).map(\.oldOffset) == [3])

        // And two lines arrived, so it falls two behind.
        let grown = """
            @@ -1,2 +1,4 @@
             one
            +added
            +added again
             two
            """
        #expect(DiffGaps.gaps(in: grown, fileLines: 9).map(\.oldOffset) == [-2])
    }

    @Test("A patch with no hunks claims nothing")
    func empty() {
        #expect(DiffGaps.gaps(in: "", fileLines: 40).isEmpty)
    }
}

/// How much of a gap one press opens.
@Suite("Opening a gap")
struct DiffGapOpeningTests {
    private func gap(_ first: Int, _ last: Int) -> DiffGaps.Gap {
        DiffGaps.Gap(afterPatchLine: 0, first: first, last: last)
    }

    /// Asking somebody to press four times for twelve lines is asking
    /// them to press four times.
    @Test("A small gap opens entirely, whichever end is pressed")
    func small() {
        for end in [DiffGaps.Opening.top, .bottom, .whole] {
            let (shown, left) = DiffGaps.remainder(of: gap(15, 26), opening: end)
            #expect(shown == 15...26)
            #expect(left == nil)
        }
    }

    @Test("A large gap opens twenty lines from the top and keeps the rest")
    func fromTheTop() {
        let (shown, left) = DiffGaps.remainder(of: gap(100, 400), opening: .top)
        #expect(shown == 100...119)
        #expect(left?.first == 120)
        #expect(left?.last == 400)
    }

    @Test("From the bottom it opens the other end")
    func fromTheBottom() {
        let (shown, left) = DiffGaps.remainder(of: gap(100, 400), opening: .bottom)
        #expect(shown == 381...400)
        #expect(left?.first == 100)
        #expect(left?.last == 380)
    }

    @Test("Asked for the whole of it, a large gap opens entirely")
    func whole() {
        let (shown, left) = DiffGaps.remainder(of: gap(100, 400), opening: .whole)
        #expect(shown == 100...400)
        #expect(left == nil)
    }
}

/// A file split into lines once, and asked about many times.
@Suite("Reading lines out of a file")
struct FileTextTests {
    @Test("Lines are counted from one")
    func fromOne() {
        let text = FileText("one\ntwo\nthree\nfour")
        #expect(text.lines(from: 2, through: 3) == ["two", "three"])
        #expect(text.lines(from: 1, through: 1) == ["one"])
    }

    /// A file ending in a newline splits into a last empty piece that is
    /// not a line of it.
    @Test("A trailing newline is not a line")
    func trailingNewline() {
        #expect(FileText("one\ntwo\n").count == 2)
        #expect(FileText("one\ntwo").count == 2)
    }

    /// A patch and a blob can disagree -- the file may have moved on --
    /// and the honest answer is the lines that exist.
    @Test("A range past the end gives what there is")
    func pastTheEnd() {
        let text = FileText("one\ntwo")
        #expect(text.lines(from: 2, through: 50) == ["two"])
        #expect(text.lines(from: 50, through: 60).isEmpty)
        #expect(text.lines(from: 0, through: 1) == ["one"])
    }
}

/// What GitHub said when asked for a file.
@Suite("Reading a file's contents back")
struct FileContentQueryTests {
    @Test("A text file comes back as its lines")
    func text() {
        let content = FileContentQuery.content(from: [
            "text": "one\ntwo", "isBinary": false, "isTruncated": false, "byteSize": 7,
        ])
        #expect(content.lines?.lines == ["one", "two"])
        #expect(content.refusal == nil)
    }

    /// Each of the three ways there is nothing to show says so, because
    /// the row has to stop offering to expand and give a reason.
    @Test("Binary, too large and missing each say so")
    func refusals() {
        #expect(FileContentQuery.content(from: ["isBinary": true]) == .binary)
        #expect(
            FileContentQuery.content(from: [
                "text": "half", "isTruncated": true, "byteSize": 900_000,
            ]) == .tooLarge(bytes: 900_000)
        )
        #expect(FileContentQuery.content(from: nil) == .missing)
        for content in [FileContent.binary, .tooLarge(bytes: 1), .missing] {
            #expect(content.refusal != nil)
            #expect(content.lines == nil)
        }
    }

    /// Every blob asked for is in the answer, including the ones that
    /// could not be read: a missing key is indistinguishable from a
    /// request nobody made.
    @Test("Every blob asked for comes back, readable or not")
    func everyBlob() {
        let found = FileContentQuery.contents(
            from: ["repository": [
                "f0": ["text": "one", "isBinary": false, "isTruncated": false],
                "f1": NSNull(),
            ]],
            blobs: ["aaa", "bbb"]
        )
        #expect(found.count == 2)
        #expect(found["aaa"]?.lines?.lines == ["one"])
        #expect(found["bbb"] == .missing)
    }

    @Test("The query names one alias per blob")
    func document() {
        let document = FileContentQuery.document(count: 2)
        #expect(document.contains("$oid0: GitObjectID!"))
        #expect(document.contains("$oid1: GitObjectID!"))
        #expect(document.contains("f1: object(oid: $oid1)"))

        let variables = FileContentQuery.variables(
            owner: "octo", name: "server", blobs: ["aaa", "bbb"]
        )
        #expect(variables["oid0"] as? String == "aaa")
        #expect(variables["oid1"] as? String == "bbb")
        #expect(variables["owner"] as? String == "octo")
    }
}

/// Which files have unchanged code worth asking for.
@Suite("Whether a file can be expanded")
struct ChangedFileExpansionTests {
    private func file(_ change: ChangedFile.Change, blob: String? = "aaa") -> ChangedFile {
        ChangedFile(
            path: "a.php", additions: 1, deletions: 1, change: change,
            patch: "@@ -1,1 +1,1 @@", blob: blob
        )
    }

    /// A file that was added is all additions and one that was removed is
    /// all removals: neither has a line that stayed the same.
    @Test("Only a file with unchanged lines in it can be expanded")
    func kinds() {
        #expect(file(.modified).canExpand)
        #expect(file(.renamed).canExpand)
        #expect(!file(.added).canExpand)
        #expect(!file(.removed).canExpand)
    }

    @Test("Without a blob there is nowhere to fetch from")
    func noBlob() {
        #expect(!file(.modified, blob: nil).canExpand)
        #expect(
            !ChangedFile(
                path: "a.png", additions: 0, deletions: 0, change: .modified,
                patch: nil, blob: "aaa"
            ).canExpand
        )
    }
}

/// What a press on a gap does, including one made before the file has
/// arrived.
@MainActor
@Suite("Opening gaps as a reader does")
struct ExpansionTests {
    private func gap(_ first: Int, _ last: Int, id: Int = 0) -> DiffGaps.Gap {
        DiffGaps.Gap(afterPatchLine: id, first: first, last: last)
    }

    @Test("A small gap goes entirely and stops offering itself")
    func small() {
        let expansion = Expansion()
        let gap = self.gap(10, 20)
        expansion.open(gap, .whole)
        #expect(expansion.shown(gap) == [10...20])
        #expect(expansion.gap(gap) == nil)
    }

    /// The press means "show me". Without this the first press only
    /// fetched and a second was needed to open what had arrived.
    @Test("A press before the file is here is carried out when it comes")
    func pending() {
        let expansion = Expansion()
        let gap = self.gap(1, 300)
        expansion.await(gap, .top)
        #expect(expansion.isAwaiting(gap))
        #expect(expansion.shown(gap).isEmpty)

        expansion.applyPending([gap])
        #expect(!expansion.isAwaiting(gap))
        #expect(expansion.shown(gap) == [1...20])
    }

    @Test("Nothing is carried out twice")
    func pendingOnce() {
        let expansion = Expansion()
        let gap = self.gap(1, 300)
        expansion.await(gap, .top)
        expansion.applyPending([gap])
        expansion.applyPending([gap])
        #expect(expansion.shown(gap) == [1...20])
    }

    /// Opening from the bottom puts the new lines at the bottom of the
    /// gap, so what is left is above them -- and the row offering it has
    /// to go above them too, or it sits between two lines that follow one
    /// another.
    @Test("The row goes above the lines when what is left is above them")
    func order() {
        let expansion = Expansion()
        let gap = self.gap(1, 300)

        expansion.open(gap, .bottom)
        #expect(expansion.shown(gap) == [281...300])
        #expect(expansion.remainderIsAbove(gap))

        let other = self.gap(1, 300, id: 1)
        expansion.open(other, .top)
        #expect(expansion.shown(other) == [1...20])
        #expect(!expansion.remainderIsAbove(other))
    }

    @Test("A gap nobody has touched has no row to place")
    func untouched() {
        let expansion = Expansion()
        #expect(!expansion.remainderIsAbove(gap(1, 300)))
    }
}
