import Foundation

/// Which lines of a patch begin inside a block comment.
///
/// A diff is drawn a line at a time, and the highlighter is handed one line
/// at a time with it. On its own, the second line of a docblock is prose --
/// and prose is full of words that are keywords in the language around it,
/// so `and` and `for` came out purple in the middle of a sentence. What the
/// line before it left open is the missing half of the answer, and this is
/// where it is worked out.
///
/// Each side of the patch is followed separately. A removed line is in the
/// old file only and an added line in the new one, so a comment opened on
/// one side says nothing about the other; only a context line, which is in
/// both, moves both.
///
/// Keyed by the line's number in its file rather than by its place in the
/// patch, because that is the one name both layouts know a line by: the
/// unified column reads the patch in order, the two-column one has already
/// paired its lines and thrown the order away.
public struct DiffComments: Sendable {
    private let old: Set<Int>
    private let new: Set<Int>

    public static let none = DiffComments(old: [], new: [])

    private init(old: Set<Int>, new: Set<Int>) {
        self.old = old
        self.new = new
    }

    public func isInsideComment(line: Int?, side: ReviewThread.Side) -> Bool {
        guard let line else { return false }
        return side == .old ? old.contains(line) : new.contains(line)
    }

    /// The same question asked by a unified row, which carries both numbers.
    ///
    /// The new file wherever there is one, which is the side such a row is
    /// showing; a line that was only removed is the other one.
    public func isInsideComment(_ number: DiffLineNumber) -> Bool {
        if let line = number.new { return isInsideComment(line: line, side: .new) }
        return isInsideComment(line: number.old, side: .old)
    }

    public static func read(_ patch: String, language: CodeLanguage?) -> DiffComments {
        // Only a comment that spans lines can leave anything open, so a
        // language without one has nothing to carry.
        guard let language, language.blockComment != nil else { return .none }

        let numbers = DiffLineNumbers.read(patch)
        var old: Set<Int> = []
        var new: Set<Int> = []
        var isOldOpen = false
        var isNewOpen = false
        var insideHunk = false

        /// Whether a comment is still open once that line has been read.
        func carries(_ body: String, from isOpen: Bool) -> Bool {
            SyntaxHighlighter.read(body, language: language, insideComment: isOpen).insideComment
        }

        for (index, line) in patch.components(separatedBy: "\n").enumerated() {
            if DiffPatchLine.isHunkHeader(line) {
                insideHunk = true
                // A hunk resumes somewhere else in the file, and whatever
                // stood between the two is not in the patch to be read. An
                // open comment carried across that gap would be a guess.
                isOldOpen = false
                isNewOpen = false
                continue
            }
            if DiffPatchLine.isNote(line)
                || DiffPatchLine.isFileHeader(line, insideHunk: insideHunk)
            {
                continue
            }

            let number = index < numbers.count ? numbers[index] : .none
            // Without the marker: the `+` or `-` is the patch's, not the
            // file's, and the views strip it the same way before painting.
            let body = DiffWords.split(line).body

            if line.hasPrefix("-") {
                if isOldOpen, let place = number.old { old.insert(place) }
                isOldOpen = carries(body, from: isOldOpen)
            } else if line.hasPrefix("+") {
                if isNewOpen, let place = number.new { new.insert(place) }
                isNewOpen = carries(body, from: isNewOpen)
            } else {
                if isOldOpen, let place = number.old { old.insert(place) }
                if isNewOpen, let place = number.new { new.insert(place) }
                // Read twice only where the two sides disagree, which they
                // do only while a comment was opened on one of them alone.
                let both = isOldOpen == isNewOpen
                isOldOpen = carries(body, from: isOldOpen)
                isNewOpen = both ? isOldOpen : carries(body, from: isNewOpen)
            }
        }

        return DiffComments(old: old, new: new)
    }
}
