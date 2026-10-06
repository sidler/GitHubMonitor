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

/// The longest line each column holds, in characters.
public struct DiffWidths: Equatable, Sendable {
    public let left: Int
    public let right: Int

    public init(left: Int, right: Int) {
        self.left = left
        self.right = right
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
    /// How long the longest line on each side is.
    ///
    /// Not for sizing the columns -- those are half the width each,
    /// whatever is in the file -- but for sizing what scrolls inside one.
    /// A row has to be as wide as the widest line beside it, or its colour
    /// band stops where its own text does and the rest of the row goes
    /// white as soon as anything is scrolled sideways.
    public static func longest(in rows: [DiffSideRow]) -> DiffWidths {
        var left = 0
        var right = 0
        for row in rows {
            guard case .pair(let leftCell, let rightCell) = row else { continue }
            left = max(left, leftCell?.text.count ?? 0)
            right = max(right, rightCell?.text.count ?? 0)
        }
        return DiffWidths(left: left, right: right)
    }

    /// A hunk header, split into the half that belongs to each file.
    ///
    /// `@@ -40,6 +40,14 @@ class Thing` says where the old file resumes
    /// and where the new one does, in one line. Two columns that each
    /// scroll on their own have nowhere to put a line belonging to both --
    /// and there is no need, because each side has a half of its own.
    ///
    /// What follows the second `@@` is the enclosing function, which git
    /// works out and which belongs to neither range. It is kept on both
    /// sides: it is the answer to "where am I" that the reader wanted.
    public static func halves(ofHunk line: String) -> (old: String, new: String) {
        var old: Substring?
        var new: Substring?
        var context: [Substring] = []
        var closed = 0

        for field in line.split(separator: " ", omittingEmptySubsequences: false).dropFirst() {
            if field == "@@" {
                closed += 1
            } else if closed > 0 {
                context.append(field)
            } else if field.hasPrefix("-"), old == nil {
                old = field
            } else if field.hasPrefix("+"), new == nil {
                new = field
            }
        }

        // A header this does not understand is shown whole on both sides
        // rather than taken apart into something that is not true.
        guard let old, let new else { return (line, line) }

        let tail = context.isEmpty ? "" : " " + context.joined(separator: " ")
        return ("@@ \(old) @@" + tail, "@@ \(new) @@" + tail)
    }

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

}
