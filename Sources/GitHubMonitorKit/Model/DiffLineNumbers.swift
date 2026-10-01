import Foundation

/// Where a line of a patch sits in the file, before and after.
///
/// Both, because a unified diff shows both versions at once: a removed line
/// has a number in the old file and none in the new, an added line the
/// reverse, and a context line the same line in two places that are rarely
/// the same number.
public struct DiffLineNumber: Equatable, Sendable {
    public let old: Int?
    public let new: Int?

    public static let none = DiffLineNumber(old: nil, new: nil)

    public init(old: Int?, new: Int?) {
        self.old = old
        self.new = new
    }
}

/// Reads the line numbers of a unified diff out of its hunk headers.
///
/// A patch does not carry a number per line; it carries a starting point per
/// hunk and leaves the counting to whoever reads it. `@@ -12,24 +12,46 @@`
/// says the old file resumes at line 12 for 24 lines and the new one at 12
/// for 46, and from there every line moves one counter, the other, or both.
///
/// Worth having rather than guessing from the line's position: the hunks of
/// one patch are not contiguous -- that is the point of hunks -- so counting
/// from the top of the patch gives the right answer only until the second
/// `@@`.
public enum DiffLineNumbers {
    /// One entry per line of the patch, in order.
    ///
    /// Lines that are in neither file -- the hunk headers themselves, and
    /// git's "\ No newline at end of file" -- carry no number at all rather
    /// than borrowing their neighbour's.
    public static func read(_ patch: String) -> [DiffLineNumber] {
        var result: [DiffLineNumber] = []
        var old = 0
        var new = 0

        for line in patch.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                if let start = starts(ofHunk: line) {
                    old = start.old
                    new = start.new
                }
                result.append(.none)
                continue
            }

            // Not a line of either file: a note from git about the last one.
            if line.hasPrefix("\\") {
                result.append(.none)
                continue
            }

            if line.hasPrefix("+") {
                result.append(DiffLineNumber(old: nil, new: new))
                new += 1
            } else if line.hasPrefix("-") {
                result.append(DiffLineNumber(old: old, new: nil))
                old += 1
            } else {
                result.append(DiffLineNumber(old: old, new: new))
                old += 1
                new += 1
            }
        }

        return result
    }

    /// The two starting lines named by a hunk header, if it names them.
    ///
    /// A header with no counts -- `@@ -8 +8 @@` -- is legal and means one
    /// line, which changes nothing here: only the starts are read.
    static func starts(ofHunk line: String) -> (old: Int, new: Int)? {
        var old: Int?
        var new: Int?

        for field in line.split(separator: " ") {
            guard field.count > 1 else { continue }
            let number = field.dropFirst().prefix { $0.isNumber }
            guard let value = Int(number) else { continue }

            if field.hasPrefix("-"), old == nil {
                old = value
            } else if field.hasPrefix("+"), new == nil {
                new = value
            }
        }

        guard let old, let new else { return nil }
        return (old, new)
    }

    /// How wide the gutter has to be to hold every number in the patch,
    /// in digits.
    ///
    /// Measured over the whole file rather than per line, so the code beside
    /// it keeps one left edge instead of stepping right at line 100.
    public static func width(of numbers: [DiffLineNumber]) -> Int {
        let largest = numbers.reduce(0) { max($0, $1.old ?? 0, $1.new ?? 0) }
        return max(String(largest).count, 1)
    }
}
