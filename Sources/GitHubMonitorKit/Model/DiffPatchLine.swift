import Foundation

/// Telling a patch's own furniture from the code it describes.
///
/// One rule, in one place, because four of them disagreed: whether a line
/// counts as a change decided which lines the alignment paired, which words
/// were marked, whether a file was drawn in one column or two, and what
/// number each line carried. Four answers to one question about one string
/// is four chances to give a different one.
public enum DiffPatchLine {
    /// Whether the line opens a hunk.
    public static func isHunkHeader(_ line: String) -> Bool {
        line.hasPrefix("@@")
    }

    /// Whether the line is one of the `--- a/x` / `+++ b/x` headers that
    /// open a patch, rather than a line of the file it describes.
    ///
    /// Position, not spelling. A diff of SQL, Lua, Markdown or C is full of
    /// lines that look exactly like a header: a removed `-- note` arrives
    /// as `--- note`, a removed Markdown rule as `---`, an added `++i;` as
    /// `+++i;`. What separates them is where they stand -- a header can
    /// only come before the first `@@`.
    ///
    /// Going by spelling alone was not merely imprecise, it was backwards:
    /// GitHub's patches carry no file headers at all, so every line such a
    /// rule caught was one of the file's own.
    public static func isFileHeader(_ line: String, insideHunk: Bool) -> Bool {
        guard !insideHunk else { return false }
        return line.hasPrefix("---") || line.hasPrefix("+++")
    }

    /// Whether the line is in only one of the two files.
    public static func isChange(_ line: String, insideHunk: Bool) -> Bool {
        guard !isFileHeader(line, insideHunk: insideHunk) else { return false }
        return line.hasPrefix("+") || line.hasPrefix("-")
    }

    /// Git's note about the line before it, which belongs to neither file.
    public static func isNote(_ line: String) -> Bool {
        line.hasPrefix("\\")
    }
}
