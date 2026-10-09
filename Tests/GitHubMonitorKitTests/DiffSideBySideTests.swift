import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Laying a unified patch out in two columns")
struct DiffSideBySideTests {
    /// Reading a marked stretch back out of the line it was found in, so
    /// the assertions can name the word rather than two numbers.
    /// A context line is the same line in both files, at two numbers that
    /// are rarely the same.
    @Test("Context sits on both sides")
    func context() {
        let rows = DiffSideBySide.rows(of: "@@ -10,1 +20,1 @@\n unchanged")
        #expect(rows[0] == .hunk("@@ -10,1 +20,1 @@"))
        #expect(rows[1] == .pair(
            left: DiffCell(text: " unchanged", number: 10),
            right: DiffCell(text: " unchanged", number: 20)
        ))
    }

    /// The whole point of the view: the line that replaced something sits
    /// beside what it replaced, rather than underneath it. Paired because
    /// the two are recognisably the same line, not because both came first.
    @Test("A removal and the addition answering it share a row")
    func paired() {
        let rows = DiffSideBySide.rows(
            of: "@@ -1,1 +1,1 @@\n-    $id = $row['id'];\n+    $id = $row['login'];"
        )
        #expect(rows.count == 2)
        guard case .pair(let left, let right) = rows[1] else { return }
        #expect(left?.number == 1)
        #expect(right?.number == 1)
        // And the word that changed is the only thing marked.
        #expect(left.map { String($0.text[range: $0.emphasis[0]]) } == "id")
        #expect(right.map { String($0.text[range: $0.emphasis[0]]) } == "login")
    }

    /// Two lines with nothing in common are not a before and after, however
    /// conveniently they are stacked. Pairing them by position is the guess
    /// this alignment exists to stop making.
    @Test("Unalike lines are not paired at all")
    func tooDifferent() {
        let rows = DiffSideBySide.rows(of: "@@ -1,1 +1,1 @@\n-was\n+is")
        #expect(rows.count == 3)
        #expect(rows[1] == .pair(left: DiffCell(text: "-was", number: 1), right: nil))
        #expect(rows[2] == .pair(left: nil, right: DiffCell(text: "+is", number: 1)))
    }

    /// Three removals, one addition, one of them a real answer: one pair
    /// and two lines on their own, in the order the patch wrote them.
    @Test("Lines with nothing opposite them face a blank")
    func unevenRun() {
        let rows = DiffSideBySide.rows(
            of: "@@ -1,3 +1,1 @@\n-use Old\n-    $total = sum($rows);\n-use Gone\n"
                + "+    $total = total($rows);"
        )
        #expect(rows.count == 4)
        #expect(rows[1] == .pair(left: DiffCell(text: "-use Old", number: 1), right: nil))
        guard case .pair(let left, let right) = rows[2] else { return }
        #expect(left?.number == 2)
        #expect(right?.number == 1)
        #expect(rows[3] == .pair(left: DiffCell(text: "-use Gone", number: 3), right: nil))
    }

    /// The pairing reaches past a line that answers nothing rather than
    /// taking the first addition it meets.
    @Test("A pair is made with the line it matches, not the next one along")
    func reachesPastFiller() {
        let rows = DiffSideBySide.rows(
            of: "@@ -1,1 +1,2 @@\n-    return $this->name;\n+    // cached since 8.3\n"
                + "+    return $this->title;"
        )
        #expect(rows.count == 3)
        #expect(rows[1] == .pair(
            left: nil, right: DiffCell(text: "+    // cached since 8.3", number: 1)
        ))
        guard case .pair(let left, let right) = rows[2] else { return }
        #expect(left?.text == "-    return $this->name;")
        #expect(right?.text == "+    return $this->title;")
    }

    /// A patch may write a run as `- + - +` rather than `- - + +`. Taking
    /// the whole run and aligning it afterwards pairs them either way; a
    /// parser that expected removals first would make four half-rows of it.
    @Test("An interleaved run still pairs up")
    func interleaved() {
        let rows = DiffSideBySide.rows(
            of: "@@ -1,2 +1,2 @@\n-$a = one();\n+$a = two();\n-$b = three();\n+$b = four();"
        )
        #expect(rows.count == 3)
        guard case .pair(let firstLeft, let firstRight) = rows[1] else { return }
        #expect(firstLeft?.text == "-$a = one();")
        #expect(firstRight?.text == "+$a = two();")
        guard case .pair(let secondLeft, let secondRight) = rows[2] else { return }
        #expect(secondLeft?.text == "-$b = three();")
        #expect(secondRight?.text == "+$b = four();")
    }

    /// Additions written before the removals they answer -- legal, and the
    /// same rule applies.
    @Test("Additions first pair the same way")
    func additionsFirst() {
        let rows = DiffSideBySide.rows(
            of: "@@ -1,1 +1,1 @@\n+$a = two();\n-$a = one();"
        )
        #expect(rows.count == 2)
        guard case .pair(let left, let right) = rows[1] else { return }
        #expect(left?.text == "-$a = one();")
        #expect(right?.text == "+$a = two();")
    }

    /// Each run is paired on its own. A removal in one run must not reach
    /// across the context line between them to an addition in the next.
    @Test("A context line ends the run")
    func runsAreSeparate() {
        let rows = DiffSideBySide.rows(of: "@@ -1,3 +1,3 @@\n-a\n keep\n+one")
        #expect(rows[1] == .pair(left: DiffCell(text: "-a", number: 1), right: nil))
        #expect(rows[2] == .pair(
            left: DiffCell(text: " keep", number: 2), right: DiffCell(text: " keep", number: 1)
        ))
        #expect(rows[3] == .pair(left: nil, right: DiffCell(text: "+one", number: 2)))
    }

    /// Belongs to neither file, so it spans both columns rather than
    /// pretending to be a line of one of them.
    @Test("A hunk header spans the row")
    func hunkSpans() {
        let rows = DiffSideBySide.rows(of: "@@ -1,1 +1,1 @@ class Thing\n a")
        #expect(rows[0] == .hunk("@@ -1,1 +1,1 @@ class Thing"))
    }

    /// Also neither file's line, and worth keeping: it is the difference
    /// between two files that otherwise read identically.
    @Test("The no-newline note is kept and spans the row")
    func noteSpans() {
        let rows = DiffSideBySide.rows(of: "@@ -1,1 +1,1 @@\n-a\n\\ No newline at end of file\n+b")
        #expect(rows.contains(.note("\\ No newline at end of file")))
        // It ends the run, so the removal and the addition do not pair
        // across it -- they are lines of different shapes.
        #expect(rows[1] == .pair(left: DiffCell(text: "-a", number: 1), right: nil))
    }

    @Test("An empty patch makes no rows worth drawing")
    func empty() {
        #expect(DiffSideBySide.rows(of: "") == [.pair(
            left: DiffCell(text: "", number: 0), right: DiffCell(text: "", number: 0)
        )])
    }

    /// The two columns size their number gutter from the rows, which are
    /// already worked out and kept; reading the patch a second time per
    /// frame was a second pass over every line. The two ways of asking must
    /// give the same answer or the gutter is the wrong width.
    @Test("The largest number in the rows is the largest in the patch")
    func gutterAgrees() {
        for patch in [
            "@@ -98,4 +98,4 @@\n a\n-b\n+c\n d",
            "@@ -1,2 +1,2 @@\n one\n-$a = one();\n+$a = two();",
            "@@ -1000,1 +2,1 @@\n-x\n+y",
            "",
        ] {
            let fromRows = DiffSideBySide.rows(of: patch).reduce(0) { widest, row in
                guard case .pair(let left, let right) = row else { return widest }
                return max(widest, left?.number ?? 0, right?.number ?? 0)
            }
            let fromPatch = DiffLineNumbers.read(patch).reduce(0) {
                max($0, $1.old ?? 0, $1.new ?? 0)
            }
            #expect(fromRows == fromPatch)
        }
    }

}

extension String {
    /// The characters a `ChangedRange` covers.
    subscript(range range: ChangedRange) -> Substring {
        let from = index(startIndex, offsetBy: range.location)
        let to = index(from, offsetBy: range.length)
        return self[from..<to]
    }
}

@Suite("Splitting the hunk header between the columns")
struct HunkHalvesTests {
    /// Two columns that each scroll on their own have nowhere to put a
    /// line belonging to both -- and no need, since each side has a half.
    @Test("Each side gets its own range")
    func halves() {
        let halves = DiffSideBySide.halves(ofHunk: "@@ -40,6 +40,14 @@ class Handler")
        #expect(halves.old == "@@ -40,6 @@ class Handler")
        #expect(halves.new == "@@ +40,14 @@ class Handler")
    }

    /// Git works the enclosing function out and it belongs to neither
    /// range. Both sides keep it: it is the answer to "where am I".
    @Test("The function around the hunk stays on both sides")
    func contextIsKept() {
        let halves = DiffSideBySide.halves(
            ofHunk: "@@ -1,2 +1,2 @@ public function matches(array $row): bool"
        )
        #expect(halves.old.hasSuffix("public function matches(array $row): bool"))
        #expect(halves.new.hasSuffix("public function matches(array $row): bool"))
    }

    @Test("A header with no trailing context ends after the second marker")
    func withoutContext() {
        let halves = DiffSideBySide.halves(ofHunk: "@@ -1,1 +1,1 @@")
        #expect(halves.old == "@@ -1,1 @@")
        #expect(halves.new == "@@ +1,1 @@")
    }

    /// A count may be left off, which means one line.
    @Test("A range without a count is still a range")
    func withoutCounts() {
        let halves = DiffSideBySide.halves(ofHunk: "@@ -8 +8 @@")
        #expect(halves.old == "@@ -8 @@")
        #expect(halves.new == "@@ +8 @@")
    }

    /// Shown whole on both sides rather than taken apart into something
    /// that is not true.
    @Test("A header this does not understand is left alone")
    func unparsed() {
        let line = "@@ something else entirely @@"
        let halves = DiffSideBySide.halves(ofHunk: line)
        #expect(halves.old == line)
        #expect(halves.new == line)
    }
}

@Suite("When two columns are worth drawing")
struct OneSidedPatchTests {
    /// A file that was added has no old version, so the left column would
    /// be half a window of nothing and every line of the new file would be
    /// squeezed into the other half to face it.
    @Test("A patch that only adds has one side")
    func added() {
        #expect(DiffSideBySide.isOneSided("@@ -0,0 +1,2 @@\n+one\n+two"))
    }

    @Test("A patch that only removes has one side")
    func removed() {
        #expect(DiffSideBySide.isOneSided("@@ -1,2 +0,0 @@\n-one\n-two"))
    }

    @Test("A patch that does both has two")
    func both() {
        #expect(!DiffSideBySide.isOneSided("@@ -1,1 +1,1 @@\n-was\n+is"))
    }

    /// Context alone is nothing to compare, whichever way it is drawn.
    @Test("A patch that changes nothing has one side")
    func unchanged() {
        #expect(DiffSideBySide.isOneSided("@@ -1,1 +1,1 @@\n unchanged"))
        #expect(DiffSideBySide.isOneSided(""))
    }

    /// `---` and `+++` name the files a patch is between. Counting them as
    /// lines would make every patch look two-sided.
    @Test("A patch's own file headers are not its lines")
    func fileHeaders() {
        #expect(DiffSideBySide.isOneSided("--- a/x\n+++ b/x\n@@ -0,0 +1,1 @@\n+only"))
    }

    /// The other half of that rule, and the half that was wrong. A header
    /// can only stand before the first `@@`; the same characters after it
    /// are a line of the file. GitHub's patches carry no headers at all,
    /// so a rule going by spelling alone only ever caught real code --
    /// and reported a file with both sides as one-sided, which dropped
    /// the two columns the reader had asked for.
    @Test("After the first hunk, --- and +++ are code")
    func markersThatLookLikeHeaders() {
        // A removed SQL comment, the only removal in the file.
        #expect(!DiffSideBySide.isOneSided(
            "@@ -1,3 +1,3 @@\n SELECT 1\n--- legacy note\n+WHERE id = 2"
        ))
        // A Markdown rule replaced by another.
        #expect(!DiffSideBySide.isOneSided("@@ -1,2 +1,2 @@\n---\n+***"))
        // A C decrement becoming an increment.
        #expect(!DiffSideBySide.isOneSided("@@ -1,2 +1,2 @@\n---i;\n+++i;"))

        // And they are drawn as what they are, on the side they belong to.
        let rows = DiffSideBySide.rows(of: "@@ -1,2 +1,2 @@\n---\n+***")
        #expect(rows.count == 3)
        guard case .pair(let left, let right) = rows[1] else {
            Issue.record("the removed rule should be a pair, got \(rows[1])")
            return
        }
        #expect(left?.text == "---")
        #expect(right == nil)
    }

    /// One column and two columns must say the same thing about the same
    /// patch -- which they did not, because each asked a different
    /// question about a line beginning `---`.
    @Test("Both layouts agree on which lines changed")
    func layoutsAgree() {
        let patch = "@@ -1,5 +1,5 @@\n-alpha = one()\n---\n-beta = two()\n+beta = twoish()\n+alpha = oneish()"
        let marks = DiffAlignment.emphasis(in: patch)
        let rows = DiffSideBySide.rows(of: patch)
        #expect(rows.count == 4)

        // The removed rule is a line of the file, so it takes the left
        // side with nothing opposite it -- and the run of changes reaches
        // across it, which is where the two layouts used to part company:
        // one treated it as a context line and broke the run there, the
        // other did not, so each paired a different removal with a
        // different addition and marked different words in both.
        guard case .pair(let rule, let nothing) = rows[2] else {
            Issue.record("expected the removed rule as a pair, got \(rows[2])")
            return
        }
        #expect(rule?.text == "---")
        #expect(nothing == nil)
        #expect(marks[2].isEmpty)

        // What two columns mark is what one column marks.
        guard case .pair(let old, let new) = rows[1] else {
            Issue.record("expected a pair, got \(rows[1])")
            return
        }
        #expect(old?.emphasis == marks[1])
        #expect(new?.emphasis == marks[4])
        #expect(old?.emphasis.isEmpty == false)
    }
}
