import Foundation

/// The stretches of a file a patch leaves out.
///
/// GitHub sends the changed lines and three either side of them. What is
/// missing is everything between one hunk and the next, plus whatever
/// comes before the first and after the last -- and that is where the
/// answer to "is this right?" usually lives.
///
/// Counted in the new file's line numbers alone, which is the whole of
/// why this is cheap: a line a patch left out is by definition a line
/// that did not change, so it reads the same in both versions. One blob,
/// the one at the head commit, fills both columns.
public enum DiffGaps {
    /// One stretch of missing lines, in new-file numbering, inclusive.
    public struct Gap: Equatable, Sendable, Identifiable {
        /// Where in the drawn patch it belongs: the number of patch lines
        /// that come before it. Zero means above everything.
        public let afterPatchLine: Int
        public let first: Int
        public let last: Int
        /// What to add to a new-file line number to get the old one.
        ///
        /// Unchanged lines exist in both files at a fixed distance apart,
        /// and that distance is what the hunk header either side of the
        /// gap states. Without it the gutter could only honestly fill one
        /// of its two columns.
        public let oldOffset: Int

        public var id: Int { afterPatchLine }
        public var count: Int { last - first + 1 }

        public init(afterPatchLine: Int, first: Int, last: Int, oldOffset: Int = 0) {
            self.afterPatchLine = afterPatchLine
            self.first = first
            self.last = last
            self.oldOffset = oldOffset
        }
    }

    /// Where the patch is silent.
    ///
    /// `total` is how many lines the file has, which is what says whether
    /// anything follows the last hunk. Without it the tail is left out
    /// rather than guessed.
    public static func gaps(in patch: String, fileLines total: Int) -> [Gap] {
        var gaps: [Gap] = []
        // Where the next line the patch accounts for should start, in new
        // numbering. The first line of a file is one.
        var expected = 1
        var newLine = 0
        var oldLine = 0
        var index = 0

        var rows = patch.components(separatedBy: "\n")
        // A patch that ends in a newline splits into a last empty piece
        // that is not a line of it. Counted as a context line it would
        // push every gap below it one line late, and a line of the file
        // would go missing without a word.
        if rows.last == "" { rows.removeLast() }

        for raw in rows {
            defer { index += 1 }
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw

            if line.hasPrefix("@@") {
                guard let starts = DiffLineNumbers.starts(ofHunk: line) else { continue }
                if starts.new > expected {
                    gaps.append(Gap(
                        afterPatchLine: index, first: expected, last: starts.new - 1,
                        oldOffset: starts.old - starts.new
                    ))
                }
                newLine = starts.new - 1
                oldLine = starts.old - 1
                expected = starts.new
                continue
            }

            // Only the two kinds of line that exist in the new file. A
            // removal is not there, and "\ No newline at end of file" is
            // a note about the file rather than a line of it.
            if line.hasPrefix("-") {
                guard newLine > 0 else { continue }
                oldLine += 1
                continue
            }
            if line.hasPrefix("+") || line.hasPrefix(" ") || line.isEmpty {
                guard newLine > 0 || !line.isEmpty else { continue }
                newLine += 1
                // An addition exists in the new file only, so it widens
                // the distance between the two.
                if !line.hasPrefix("+") { oldLine += 1 }
                expected = newLine + 1
            }
        }

        // Whatever follows the last hunk.
        if total >= expected, newLine > 0 {
            gaps.append(Gap(
                afterPatchLine: index, first: expected, last: total,
                oldOffset: oldLine - newLine
            ))
        }
        return gaps
    }

    /// How much of a gap one press should open.
    ///
    /// A small gap goes entirely: asking somebody to press four times for
    /// twelve lines is asking them to press four times. A large one opens
    /// from the end being read towards the middle, the way GitHub's own
    /// chevrons do, and what is left stays a gap.
    public static let step = 20
    public static let openWholeUpTo = 50

    /// What a gap becomes when it is opened from one end.
    ///
    /// Nil where nothing is left, which is how the row knows to stop
    /// offering itself.
    public static func remainder(
        of gap: Gap, opening end: Opening
    ) -> (shown: ClosedRange<Int>, left: Gap?) {
        if gap.count <= openWholeUpTo {
            return (gap.first...gap.last, nil)
        }
        switch end {
        case .top:
            let shown = gap.first...(gap.first + step - 1)
            return (shown, Gap(
                afterPatchLine: gap.afterPatchLine,
                first: shown.upperBound + 1,
                last: gap.last
            ))
        case .bottom:
            let shown = (gap.last - step + 1)...gap.last
            return (shown, Gap(
                afterPatchLine: gap.afterPatchLine,
                first: gap.first,
                last: shown.lowerBound - 1
            ))
        case .whole:
            return (gap.first...gap.last, nil)
        }
    }

    public enum Opening: Sendable { case top, bottom, whole }
}
