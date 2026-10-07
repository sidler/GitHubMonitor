import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Finding what changed inside a line")
struct DiffWordsTests {
    private func marked(_ line: String, _ ranges: [ChangedRange]) -> [String] {
        ranges.map { String(line[range: $0]) }
    }

    /// Punctuation on its own is what keeps a one-word rename from painting
    /// half the expression.
    @Test("Identifiers hold together, punctuation stands alone")
    func tokens() {
        #expect(DiffWords.tokens("$row['id'];").map(String.init)
            == ["$", "row", "[", "'", "id", "'", "]", ";"])
        // A run of spaces is one token, so indentation is one thing to
        // compare rather than four.
        #expect(DiffWords.tokens("    a").map(String.init) == ["    ", "a"])
        #expect(DiffWords.tokens("").isEmpty)
    }

    /// The case the whole feature is for: one word swapped in a line that is
    /// otherwise identical.
    @Test("A renamed word is the only thing marked")
    func rename() {
        let old = "-    $id = $row['id'];"
        let new = "+    $id = $row['login'];"
        let comparison = DiffWords.compare(old, new)
        #expect(marked(old, comparison.old) == ["id"])
        #expect(marked(new, comparison.new) == ["login"])
        #expect(comparison.similarity > DiffAlignment.threshold)
    }

    /// Without dropping the marker, no removal is ever equal to any addition
    /// and the first character of every line is marked.
    @Test("The marker column is not part of the comparison")
    func markerIgnored() {
        let comparison = DiffWords.compare("-same line", "+same line")
        #expect(comparison.old.isEmpty)
        #expect(comparison.new.isEmpty)
        #expect(comparison.similarity == 1)
    }

    /// Ranges are reported against the whole line, marker included, because
    /// that is what gets drawn.
    @Test("Offsets count from the start of the line as written")
    func offsetsIncludeTheMarker() {
        let new = "+ab cd"
        let comparison = DiffWords.compare("-ab xy", new)
        #expect(marked(new, comparison.new) == ["cd"])
        // "+ab " is four characters, so the change starts at four.
        #expect(comparison.new.first?.location == 4)
    }

    /// Changed tokens that touch become one mark; ones with something
    /// unchanged between them stay apart. In `$row->id` becoming
    /// `$this->name` the arrow did not change, so the two renamed parts are
    /// marked separately -- which is also what they are.
    @Test("Changes that touch join, changes with something between do not")
    func merging() {
        let new = "+$this->name;"
        let comparison = DiffWords.compare("-$row->id;", new)
        #expect(marked(new, comparison.new) == ["this", "name"])

        // `'id'` to `'login'` would be three marks if neighbours did not
        // join: the word and the quotes around it all changed together.
        let quoted = "+$row[\"login\"];"
        #expect(marked(quoted, DiffWords.compare("-$row['id'];", quoted).new)
            == ["\"login\""])
    }

    /// Chosen deliberately: a line that only moved sideways should say so.
    /// Nothing is visible inside the mark, but the band shows where it is.
    @Test("A change in indentation alone is still marked")
    func indentation() {
        let old = "-    return true;"
        let new = "+        return true;"
        let comparison = DiffWords.compare(old, new)
        #expect(!comparison.new.isEmpty)
        #expect(marked(new, comparison.new) == ["        "])
        // And the two are still obviously the same line.
        #expect(comparison.similarity == 1)
    }

    /// Indentation would otherwise make every pair of deeply nested lines
    /// look alike: two unrelated statements eight levels in share eight
    /// spaces and little else, and at some depth that alone would pair
    /// them. The same two lines score the same however far they are
    /// indented.
    @Test("Whitespace does not count towards the score")
    func whitespaceIsNotLikeness() {
        let bare = DiffWords.compare("-$a = one();", "+$b = two();").similarity
        let deep = DiffWords.compare(
            "-" + String(repeating: " ", count: 32) + "$a = one();",
            "+" + String(repeating: " ", count: 32) + "$b = two();"
        ).similarity
        #expect(bare == deep)

        // Two lines that are not the same statement do not pair, however
        // much indentation they have in common.
        #expect(DiffWords.compare(
            "-        use Platform\\Session\\Handler;",
            "+        $this->logger->warning('cache miss');"
        ).similarity < DiffAlignment.threshold)
    }

    /// Nobody reads a minified line word by word, and the comparison is
    /// quadratic in the number of words.
    @Test("A very long line is not compared word by word")
    func longLine() {
        let long = "+" + String(repeating: "a", count: DiffWords.longestComparable + 1)
        let comparison = DiffWords.compare(long, long)
        #expect(comparison.old.isEmpty)
        // Identical is still identical, so it can still be paired.
        #expect(comparison.similarity == 1)
    }

    @Test("A line replaced outright shares nothing")
    func unrelated() {
        #expect(DiffWords.compare("-use Old;", "+$total = sum($rows);").similarity
            < DiffAlignment.threshold)
    }
}

@Suite("Lining up a block of removals against the additions")
struct DiffAlignmentTests {
    @Test("Each line is paired with the one it matches")
    func pairs() {
        let result = DiffAlignment.pairs(
            removed: ["-use Old;", "-    $a = one();"],
            added: ["-    $a = two();"]
        )
        #expect(result == [
            DiffAlignment.Pair(old: 0, new: nil),
            DiffAlignment.Pair(old: 1, new: 0),
        ])
    }

    /// Order is kept, so a pair never reaches backwards past one already
    /// made -- which would draw two lines crossing over each other.
    ///
    /// Asserted as the property rather than on one example: both indices
    /// must rise down the rows, which rules out crossing, repeating a line,
    /// and dropping one.
    @Test(
        "Both sides only ever move forwards",
        arguments: [
            (["-alpha($x);", "-beta($y);"], ["+beta($z);", "+alpha($w);"]),
            (["-$a = one();", "-gone();", "-$b = three();"], ["+$b = four();", "+$a = two();"]),
            (["-only"], ["+a", "+b", "+c"]),
        ]
    )
    func keepsOrder(removed: [String], added: [String]) {
        var lastOld = -1
        var lastNew = -1
        var seenOld = 0
        var seenNew = 0
        for pair in DiffAlignment.pairs(removed: removed, added: added) {
            if let old = pair.old {
                #expect(old > lastOld)
                lastOld = old
                seenOld += 1
            }
            if let new = pair.new {
                #expect(new > lastNew)
                lastNew = new
                seenNew += 1
            }
        }
        // And every line is placed exactly once.
        #expect(seenOld == removed.count)
        #expect(seenNew == added.count)
    }

    @Test("A block with nothing on one side is all half-rows")
    func oneSided() {
        #expect(DiffAlignment.pairs(removed: [], added: ["+a", "+b"]) == [
            DiffAlignment.Pair(old: nil, new: 0),
            DiffAlignment.Pair(old: nil, new: 1),
        ])
        #expect(DiffAlignment.pairs(removed: ["-a"], added: []) == [
            DiffAlignment.Pair(old: 0, new: nil),
        ])
    }

    /// A thousand lines replaced by a thousand others is a generated file.
    /// Above the cap it falls back to what the app did before, rather than
    /// stopping the window to work out an alignment nobody will read.
    @Test("A very large block is paired by position instead")
    func cap() {
        let size = 200
        let removed = (0..<size).map { "-line \($0)" }
        let added = (0..<size).map { "+line \($0) changed" }
        #expect(size * size > DiffAlignment.mostComparisons)
        let result = DiffAlignment.pairs(removed: removed, added: added)
        #expect(result.count == size)
        #expect(result[7] == DiffAlignment.Pair(old: 7, new: 7))
    }

    /// A context line is an anchor: a removal above it must not pair with
    /// an addition below it.
    @Test("Pairing does not reach across a context line")
    func runsAreSeparate() {
        let marks = DiffAlignment.emphasis(
            in: "@@ -1,3 +1,3 @@\n-    $a = one();\n keep\n+    $a = two();"
        )
        #expect(marks[1].isEmpty)
        #expect(marks[3].isEmpty)
    }

    /// Both layouts read this, so the words marked in one column and in two
    /// are the same words.
    @Test("Every line of the patch gets an entry, marked or not")
    func perLine() {
        let patch = "@@ -1,2 +1,2 @@\n context\n-    $a = one();\n+    $a = two();"
        let marks = DiffAlignment.emphasis(in: patch)
        #expect(marks.count == patch.components(separatedBy: "\n").count)
        #expect(marks[0].isEmpty)   // the hunk header
        #expect(marks[1].isEmpty)   // context
        #expect(!marks[2].isEmpty)
        #expect(!marks[3].isEmpty)
    }

    /// Nothing is marked where the two lines are not a before and after:
    /// painting all of both would claim they were.
    @Test("Unalike lines are left unmarked")
    func unpairedUnmarked() {
        let marks = DiffAlignment.emphasis(in: "@@ -1,1 +1,1 @@\n-was\n+is")
        #expect(marks[1].isEmpty)
        #expect(marks[2].isEmpty)
    }
}

@Suite("Taking the marker off a line")
struct DiffMarkerSplitTests {
    /// Drawn apart because a wrapped line has to be told from a new one:
    /// with the marker in the text, the second half of a long line starts
    /// where a `+` would be and reads as a line of its own.
    @Test("The marker comes off and the code stays whole")
    func split() {
        let split = DiffWords.split("+    return true;")
        #expect(split.marker == "+")
        #expect(split.body == "    return true;")
    }

    @Test("A context line's leading space is a marker too")
    func context() {
        #expect(DiffWords.split("     $copy = clone $this;").marker == " ")
    }

    /// A hunk header has no marker column, and taking its first character
    /// off would eat the `@`.
    @Test("A line with no marker keeps all of itself")
    func unmarked() {
        let split = DiffWords.split("@@ -1,2 +1,2 @@")
        #expect(split.marker.isEmpty)
        #expect(split.body == "@@ -1,2 +1,2 @@")
    }

    /// The marked stretches are measured against the whole line, so they
    /// have to move with it or the wrong words are drawn bold.
    @Test("The marked stretches move with the text")
    func emphasisMoves() {
        let line = "+    $id = $row['login'];"
        let found = DiffWords.compare("-    $id = $row['id'];", line)
        let split = DiffWords.split(line, emphasis: found.new)

        #expect(split.emphasis.first?.location == found.new.first!.location - 1)
        // And it still covers the same word.
        let from = split.body.index(split.body.startIndex, offsetBy: split.emphasis[0].location)
        let to = split.body.index(from, offsetBy: split.emphasis[0].length)
        #expect(String(split.body[from..<to]) == "login")
    }

    /// A stretch that begins at the marker itself has nothing left of it
    /// once the marker is gone.
    @Test("A stretch covering only the marker disappears with it")
    func emphasisOnTheMarker() {
        let split = DiffWords.split(
            "+abc", emphasis: [ChangedRange(location: 0, length: 1)]
        )
        #expect(split.emphasis.isEmpty)
    }
}
