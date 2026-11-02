import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Comments that run past the end of their line")
struct DiffCommentsTests {
    /// A docblock added whole, which is what a diff of new PHP is mostly
    /// made of.
    private let added = """
        @@ -1,2 +1,6 @@
         <?php
        +/**
        + * Moves the BIA and clears what only the previous version has.
        + */
        +public function move(): void {}
         final class Thing
        """

    @Test("The lines under a docblock's opening know they are inside it")
    func insideAnAddedDocblock() {
        let state = DiffComments.read(added, language: .php)
        // The line that opens the comment is not yet inside one.
        #expect(!state.isInsideComment(line: 2, side: .new))
        #expect(state.isInsideComment(line: 3, side: .new))
        #expect(state.isInsideComment(line: 4, side: .new))
        // And the declaration under it is code again.
        #expect(!state.isInsideComment(line: 5, side: .new))
    }

    @Test("Prose in an added docblock is painted as a comment")
    func proseStaysAComment() {
        let state = DiffComments.read(added, language: .php)
        let line = " * Moves the BIA and clears what only the previous version has."
        let painted = SyntaxHighlighter.tokens(
            line, language: .php,
            insideComment: state.isInsideComment(line: 3, side: .new)
        )
        #expect(painted.map(\.kind) == [.comment])
    }

    /// A removed line is in the old file only, so a comment it opens says
    /// nothing about the file being written.
    @Test("A comment opened on one side says nothing about the other")
    func sidesAreFollowedApart() {
        let patch = """
            @@ -1,3 +1,2 @@
            -/* an old note
            -   that ran on */
            +$x = 1;
             return $x;
            """
        let state = DiffComments.read(patch, language: .php)
        #expect(state.isInsideComment(line: 2, side: .old))
        #expect(!state.isInsideComment(line: 1, side: .new))
        #expect(!state.isInsideComment(line: 2, side: .new))
    }

    /// Hunks are not contiguous. Whatever stood between them is not in the
    /// patch, so a comment left open at the end of one is not evidence
    /// about the start of the next.
    @Test("An open comment does not cross a hunk header")
    func hunksStartAfresh() {
        let patch = """
            @@ -1,1 +1,2 @@
            +/* opened and never closed
            @@ -10,1 +10,2 @@
            +for ($i = 0; $i < 3; $i++) {
            """
        let state = DiffComments.read(patch, language: .php)
        #expect(!state.isInsideComment(line: 10, side: .new))
    }

    @Test("A language with no block comment has nothing to carry")
    func nothingToCarry() {
        let patch = "@@ -1,1 +1,1 @@\n+# a note\n"
        #expect(!DiffComments.read(patch, language: .yaml).isInsideComment(line: 1, side: .new))
        #expect(!DiffComments.read(patch, language: nil).isInsideComment(line: 1, side: .new))
    }

    /// The unified column has both of a line's numbers and asks with the
    /// pair; the side it is showing is the new file wherever there is one.
    @Test("A unified row asks with the pair of numbers it carries")
    func unifiedRowsAsk() {
        let state = DiffComments.read(added, language: .php)
        #expect(state.isInsideComment(DiffLineNumber(old: nil, new: 3)))
        #expect(!state.isInsideComment(DiffLineNumber(old: nil, new: 5)))
        #expect(!state.isInsideComment(.none))
    }

    @Test("A patch already read comes back from the cache")
    @MainActor
    func cached() {
        DiffCache.shared.forget()
        let first = DiffCache.shared.comments(in: added, language: .php)
        let again = DiffCache.shared.comments(in: added, language: .php)
        #expect(first.isInsideComment(line: 3, side: .new))
        #expect(again.isInsideComment(line: 3, side: .new))
        // Asked about in another language it is worked out afresh, rather
        // than answered with what PHP made of it.
        #expect(!DiffCache.shared.comments(in: added, language: .yaml)
            .isInsideComment(line: 3, side: .new))
    }
}

/// The scan skips any line holding neither comment marker, on the grounds
/// that such a line cannot open or close one. Nearly every line of a file
/// takes that way, so it has to give the same answer as reading them all.
@Suite("The short way through the comment scan")
struct CommentScanShortcutTests {
    /// Every shape that could tempt the shortcut into the wrong answer:
    /// a docblock, a marker inside a string, a marker after a line
    /// comment, an empty line inside a comment, and plain code.
    private let patch = """
        @@ -1,16 +1,16 @@ class Thing
         <?php
        -    $old = 1;
        +    $new = 2;
         /**
          * A docblock, whose middle lines hold no marker at all.
          *
          * @param string $id
          */
             public function one(): void
             {
                 $a = '/* not a comment, a string */';
                 // a line comment mentioning /* and */
                 $b = 2;
             }
         /* opened here
            and still open
            closed here */
             $c = 3;
        """

    /// What the scan would say if every line went to the highlighter.
    private func readingEveryLine(_ patch: String, language: CodeLanguage) -> [Int: Bool] {
        var isOpen = false
        var answer: [Int: Bool] = [:]
        var number = 0
        for line in patch.components(separatedBy: "\n") {
            guard !DiffPatchLine.isHunkHeader(line), !line.hasPrefix("-") else { continue }
            number += 1
            answer[number] = isOpen
            let body = DiffWords.split(line).body
            isOpen = SyntaxHighlighter.read(
                body, language: language, insideComment: isOpen
            ).insideComment
        }
        return answer
    }

    @Test("It agrees with reading every line")
    func agrees() {
        let comments = DiffComments.read(patch, language: .php)
        let full = readingEveryLine(patch, language: .php)
        for (number, expected) in full {
            #expect(
                comments.isInsideComment(line: number, side: .new) == expected,
                "line \(number) disagrees"
            )
        }
        // And the thing is worth testing: some line really is inside one.
        #expect(full.values.contains(true))
    }

    /// A language with no block comment never reaches the scan at all.
    @Test("A language without block comments carries nothing")
    func noBlockComment() {
        #expect(DiffComments.read(patch, language: nil).isInsideComment(line: 5, side: .new) == false)
    }
}
