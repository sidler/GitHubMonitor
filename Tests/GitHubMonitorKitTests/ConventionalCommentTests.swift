import Foundation
import Testing

@testable import GitHubMonitorKit

/// The word a remark opens with: what gets written, and what is recognised
/// when one is already there.
@Suite("Conventional comments")
struct ConventionalCommentTests {
    /// Byte for byte what `pullpo-io/conventional-comments-helper` writes,
    /// which is the point: a remark from here has to sit beside one from
    /// the extension looking the same, not merely similar.
    @Test("A labelled badge is the bytes the extension writes")
    func badge() {
        #expect(
            ConventionalComment.badge(label: "issue", decoration: "blocking")
                == "[![issue(blocking)]"
                + "(https://img.shields.io/badge/issue-blocking-374151?labelColor=EF4444)]"
                + "(https://pullpo.io/cc?l=issue&d=blocking) "
        )
    }

    /// No decoration, so the badge is one half and takes the label's own
    /// colour.
    @Test("A badge without a decoration is one half")
    func bare() {
        #expect(
            ConventionalComment.badge(label: "praise")
                == "[![praise](https://img.shields.io/badge/praise-28A745)]"
                + "(https://pullpo.io/cc?l=praise) "
        )
    }

    /// shields.io reads a single dash as the divider between the halves,
    /// so a dash inside a word is written twice to mean itself. Both
    /// decorations that have one would otherwise come out cut in half.
    @Test("A dash inside a word is doubled, not read as the divider")
    func dashes() {
        #expect(
            ConventionalComment.badge(label: "nitpick", decoration: "non-blocking")
                .contains("/badge/nitpick-non--blocking-9CA3AF?labelColor=F59E0B")
        )
        #expect(
            ConventionalComment.badge(label: "todo", decoration: "if-minor")
                .contains("/badge/todo-if--minor-14B8A6?labelColor=E879F9")
        )
    }

    @Test("A badge already there is read back")
    func readBadge() {
        let text = ConventionalComment.badge(label: "question", decoration: "if-minor")
            + "Does this matter?"
        let head = ConventionalComment.head(of: text)
        #expect(head?.label == "question")
        #expect(head?.decoration == "if-minor")
        #expect(String(text.dropFirst(head?.length ?? 0)) == "Does this matter?")
    }

    /// The form the standard itself writes. Plenty of people type it by
    /// hand, and a chip pressed over one of those has to replace it
    /// rather than put a badge in front of it.
    @Test("The plain form the standard specifies is read back too")
    func readPlain() {
        let head = ConventionalComment.head(of: "issue (blocking): the lock is not held")
        #expect(head?.label == "issue")
        #expect(head?.decoration == "blocking")

        let bare = ConventionalComment.head(of: "praise: beautiful test")
        #expect(bare?.label == "praise")
        #expect(bare?.decoration == nil)

        let bold = ConventionalComment.head(of: "**suggestion:** rename this")
        #expect(bold?.label == "suggestion")
    }

    /// Ordinary prose is not a head, however it begins.
    @Test("A sentence that merely starts with a word is left alone")
    func notAHead() {
        #expect(ConventionalComment.head(of: "questionable naming here") == nil)
        #expect(ConventionalComment.head(of: "the issue is the lock") == nil)
        #expect(ConventionalComment.head(of: "") == nil)
    }

    /// The whole reason the head is parsed rather than just prepended.
    @Test("A second word replaces the first instead of stacking on it")
    func replaces() {
        let first = ConventionalComment.applying(label: "nitpick", to: "rename this")
        let second = ConventionalComment.applying(label: "suggestion", to: first.text)
        #expect(ConventionalComment.head(of: second.text)?.label == "suggestion")
        #expect(!second.text.contains("nitpick"))
        #expect(second.text.hasSuffix("rename this"))
    }

    /// Pressing the lit chip again, which is the only way back to an
    /// unlabelled remark without editing markdown by hand.
    @Test("Taking the word off leaves the prose")
    func removes() {
        let on = ConventionalComment.applying(label: "chore", to: "run the CI job")
        let off = ConventionalComment.applying(label: nil, to: on.text)
        #expect(off.text == "run the CI job")
        #expect(off.bodyStart == 0)
    }

    /// A decoration is kept when the word beside it changes, because the
    /// two are chosen separately and only one chip was pressed.
    @Test("Changing the word keeps the decoration")
    func keepsDecoration() {
        let first = ConventionalComment.applying(
            label: "issue", decoration: "blocking", to: "the lock"
        )
        let head = ConventionalComment.head(of: first.text)
        let second = ConventionalComment.applying(
            label: "question", decoration: head?.decoration, to: first.text
        )
        #expect(ConventionalComment.head(of: second.text)?.decoration == "blocking")
    }

    /// The caret follows the writing rather than being thrown to the
    /// start -- or, worse, left sitting inside the badge's URL.
    @Test("The caret stays in the prose when a word is put on")
    func caretFollowsTheProse() {
        let text = "rename this"
        let rewrite = ConventionalComment.applying(label: "nitpick", to: text)
        // The caret was at the end of eleven characters of prose.
        #expect(rewrite.caret(from: 11) == rewrite.bodyStart + 11)
        // A caret that was inside the old head has nowhere to go but the
        // start of the prose.
        #expect(rewrite.caret(from: 0) == rewrite.bodyStart)
    }

    @Test("The caret comes back with the prose when the word is taken off")
    func caretAfterRemoval() {
        let on = ConventionalComment.applying(label: "todo", to: "fix the typo")
        let off = ConventionalComment.applying(label: nil, to: on.text)
        #expect(off.caret(from: on.bodyStart + 3) == 3)
    }

    /// The standard's nine, then its three expressive extras.
    @Test("All twelve words and all three decorations are offered")
    func theWholeList() {
        #expect(
            ConventionalComment.labels.map(\.name) == [
                "praise", "nitpick", "suggestion", "issue", "todo", "question",
                "thought", "chore", "note", "typo", "polish", "quibble",
            ]
        )
        #expect(
            ConventionalComment.decorations.map(\.name)
                == ["non-blocking", "blocking", "if-minor"]
        )
    }

    /// A colour that cannot be read is a chip drawn in the fallback grey
    /// and a badge in some other colour than the chip, which is exactly
    /// the disagreement this list exists to prevent.
    @Test("Every colour is six hex digits and readable")
    func colours() {
        for label in ConventionalComment.labels + ConventionalComment.decorations {
            #expect(label.colour.count == 6, "\(label.name) is not six digits")
            #expect(label.components != nil, "\(label.name) has an unreadable colour")
            #expect(!label.summary.isEmpty, "\(label.name) says nothing about itself")
        }
    }
}
