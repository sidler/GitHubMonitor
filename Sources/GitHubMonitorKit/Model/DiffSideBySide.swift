import Foundation

/// One side of one row of a side-by-side diff.
///
/// The text keeps its marker column -- the leading `+`, `-` or space the
/// patch came with. Dropping it would shift one side against the other by a
/// character, and the syntax highlighter is already fed whole patch lines.
public struct DiffCell: Equatable, Sendable {
    public let text: String
    /// The line's number in that side's file. Nil only where the patch
    /// itself gives no number.
    public let number: Int?
    /// Which stretches of this line are not in the line opposite. Empty
    /// where there is no line opposite, or where the two are too unlike to
    /// be a before and after.
    public let emphasis: [ChangedRange]

    public init(text: String, number: Int?, emphasis: [ChangedRange] = []) {
        self.text = text
        self.number = number
        self.emphasis = emphasis
    }
}

/// One row of a side-by-side diff.
public enum DiffSideRow: Equatable, Sendable {
    /// A hunk header, which belongs to neither file and spans both columns.
    case hunk(String)
    /// Git's note that a file does not end in a newline. Also neither
    /// file's line, but worth keeping: it is the difference between two
    /// files that otherwise read identically.
    case note(String)
    /// A line of the old file, of the new one, or of both. Nil on one side
    /// is a line that exists only in the other.
    case pair(left: DiffCell?, right: DiffCell?)
}

/// How many characters wide each part of a side-by-side patch has to be.
public struct DiffWidths: Equatable, Sendable {
    /// The old file's longest line.
    public let left: Int
    /// The new file's longest line.
    public let right: Int
    /// The longest line that spans both columns: a hunk header or git's
    /// note. Neither column alone has to hold it, but the pair of them do.
    public let span: Int

    public init(left: Int, right: Int, span: Int) {
        self.left = left
        self.right = right
        self.span = span
    }
}

/// Turns a unified patch into two columns.
///
/// A unified diff is one column by construction: a removal and the line
/// that replaced it are written one after another, and which addition
/// answers which removal is left to the reader. Side by side has to decide,
/// because the two have to sit on one row.
///
/// The rule is the one every diff viewer uses: within a run of changed
/// lines, the first removal pairs with the first addition, the second with
/// the second, and whatever is left over on either side faces a blank. It
/// is a guess -- a four-line removal answered by one addition pairs three
/// blanks that no algorithm can place better without reading the code --
/// but it is the guess that puts a renamed variable next to its old name,
/// which is what the view is for.
public enum DiffSideBySide {
    public static func rows(of patch: String) -> [DiffSideRow] {
        let lines = patch.components(separatedBy: "\n")
        let numbers = DiffLineNumbers.read(patch)
        var rows: [DiffSideRow] = []
        var index = 0

        func number(at position: Int) -> DiffLineNumber {
            position < numbers.count ? numbers[position] : .none
        }

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("@@") {
                rows.append(.hunk(line))
                index += 1
                continue
            }

            if line.hasPrefix("\\") {
                rows.append(.note(line))
                index += 1
                continue
            }

            guard line.hasPrefix("+") || line.hasPrefix("-") else {
                // Context: the same line in both files, at two numbers that
                // are rarely the same.
                let place = number(at: index)
                rows.append(.pair(
                    left: DiffCell(text: line, number: place.old),
                    right: DiffCell(text: line, number: place.new)
                ))
                index += 1
                continue
            }

            // A run of changed lines, taken whole rather than as "removals
            // then additions": a patch may interleave them, and splitting
            // the run afterwards pairs them correctly either way.
            var removed: [(text: String, number: Int?)] = []
            var added: [(text: String, number: Int?)] = []
            while index < lines.count {
                let changed = lines[index]
                if changed.hasPrefix("-") {
                    removed.append((changed, number(at: index).old))
                } else if changed.hasPrefix("+") {
                    added.append((changed, number(at: index).new))
                } else {
                    break
                }
                index += 1
            }

            for pair in DiffAlignment.pairs(
                removed: removed.map(\.text), added: added.map(\.text)
            ) {
                let old = pair.old.map { removed[$0] }
                let new = pair.new.map { added[$0] }
                // Only a real pair is marked word by word. Where the
                // alignment fell back to pairing by position the two lines
                // are not a before and after, and marking all of both would
                // claim they were.
                let comparison = old.flatMap { old in
                    new.map { DiffWords.compare(old.text, $0.text) }
                }
                let marked = (comparison?.similarity ?? 0) >= DiffAlignment.threshold

                rows.append(.pair(
                    left: old.map {
                        DiffCell(
                            text: $0.text, number: $0.number,
                            emphasis: marked ? comparison?.old ?? [] : []
                        )
                    },
                    right: new.map {
                        DiffCell(
                            text: $0.text, number: $0.number,
                            emphasis: marked ? comparison?.new ?? [] : []
                        )
                    }
                ))
            }
        }

        return rows
    }

    /// The longest line each column has to hold, in characters.
    ///
    /// Measured per side rather than over the whole patch. Giving both
    /// columns the width of the file's longest line keeps the divider in
    /// the same place everywhere, but it also pads the short side to match
    /// the long one -- so a file with one wide line pushes the second
    /// column off the edge for no reason. Where neither side needs more
    /// than half, both get exactly half and the divider is centred, which
    /// is most files.
    public static func widths(of rows: [DiffSideRow]) -> DiffWidths {
        var left = 0
        var right = 0
        var span = 0

        for row in rows {
            switch row {
            case .hunk(let text), .note(let text):
                span = max(span, text.count)
            case .pair(let leftCell, let rightCell):
                left = max(left, leftCell?.text.count ?? 0)
                right = max(right, rightCell?.text.count ?? 0)
            }
        }

        return DiffWidths(left: left, right: right, span: span)
    }
}
