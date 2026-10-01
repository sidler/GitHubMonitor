import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("The line numbers down the side of a diff")
struct DiffLineNumbersTests {
    /// The shape of every patch: a header that says where both files
    /// resume, then lines that move one counter, the other, or both.
    @Test("Context moves both counters, a change moves one")
    func counting() {
        let numbers = DiffLineNumbers.read(
            """
            @@ -10,3 +20,4 @@ class Thing
             context
            -gone
            +new
             after
            """
        )
        #expect(numbers[0] == .none)                               // the header
        #expect(numbers[1] == DiffLineNumber(old: 10, new: 20))
        #expect(numbers[2] == DiffLineNumber(old: 11, new: nil))   // removed
        #expect(numbers[3] == DiffLineNumber(old: nil, new: 21))   // added
        // The removal moved only the old file on, the addition only the new,
        // so the line after them is 12 and 22 rather than 13 and 23.
        #expect(numbers[4] == DiffLineNumber(old: 12, new: 22))
    }

    /// The reason for reading the headers at all: hunks are not contiguous,
    /// so counting from the top of the patch is right only until the second.
    @Test("A second hunk starts where it says, not where the first ended")
    func secondHunk() {
        let numbers = DiffLineNumbers.read(
            """
            @@ -1,2 +1,2 @@
             one
            @@ -80,2 +91,2 @@
             far below
            """
        )
        #expect(numbers[1] == DiffLineNumber(old: 1, new: 1))
        #expect(numbers[3] == DiffLineNumber(old: 80, new: 91))
    }

    /// Legal, and means one line. Only the starts are read, so it changes
    /// nothing -- but a parser that insisted on the comma would give up here
    /// and number the rest of the file from wherever it had got to.
    @Test("A header without counts is still a header")
    func headerWithoutCounts() {
        #expect(DiffLineNumbers.starts(ofHunk: "@@ -8 +8 @@").map(\.old) == 8)
        #expect(DiffLineNumbers.starts(ofHunk: "@@ -12,24 +30,46 @@ class X")! == (12, 30))
        #expect(DiffLineNumbers.starts(ofHunk: "@@ nonsense @@") == nil)
    }

    /// Git's note about a missing trailing newline is not a line of either
    /// file, and numbering it would push everything below it out by one.
    @Test("The no-newline marker carries no number")
    func noNewlineMarker() {
        let numbers = DiffLineNumbers.read("@@ -1,1 +1,1 @@\n-old\n\\ No newline at end of file\n+new")
        #expect(numbers[2] == .none)
        #expect(numbers[3] == DiffLineNumber(old: nil, new: 1))
    }

    /// One width for the whole file, so the code beside it keeps a single
    /// left edge instead of stepping right at line 100.
    @Test("The gutter is as wide as the largest number in the file")
    func width() {
        let numbers = DiffLineNumbers.read("@@ -98,4 +98,4 @@\n a\n b\n c\n d")
        #expect(DiffLineNumbers.width(of: numbers) == 3)
        // Never nothing: a patch with no numbers at all still needs a column
        // to put the blanks in.
        #expect(DiffLineNumbers.width(of: []) == 1)
    }

    /// Right-aligned by padding rather than by frames: in a monospaced font
    /// that is what lines the columns up, and it needs no measurement.
    @Test("Numbers are padded to the gutter's width")
    func padding() {
        #expect(PatchLines.pad(7, to: 3) == "  7")
        #expect(PatchLines.pad(123, to: 3) == "123")
        // A line in only one of the files leaves the other column empty,
        // and the empty column still has to hold its place.
        #expect(PatchLines.pad(nil, to: 3) == "   ")
    }

    /// Every line of a patch gets an entry, so the view can index the two
    /// lists against each other without checking lengths.
    @Test("There is one entry per line, whatever the line is")
    func oneEntryPerLine() {
        let patch = "@@ -1,2 +1,2 @@\n a\n-b\n+c\n"
        #expect(DiffLineNumbers.read(patch).count == patch.components(separatedBy: "\n").count)
        #expect(DiffLineNumbers.read("").count == 1)
    }
}
