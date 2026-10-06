import Foundation

/// Which removed line answers which added one.
///
/// A unified patch does not say. It writes a block of removals followed by a
/// block of additions and leaves the reader to work out that the third
/// removal became the first addition. Pairing them by position -- first with
/// first, second with second -- is right only when the two blocks are the
/// same length and nothing moved, which is the case a reader needs no help
/// with.
public enum DiffAlignment {
    /// How alike two lines have to be before they are called a pair.
    ///
    /// Measured over words, whitespace left out. At this level a signature
    /// that gained a type is still itself, and two unrelated statements that
    /// happen to share a bracket are not.
    public static let threshold = 0.4

    /// Above this many comparisons the block is paired by position instead.
    ///
    /// The alignment is quadratic in the number of lines, each comparison
    /// quadratic again in the number of words. A thousand lines replaced by
    /// a thousand others is a generated file, and nobody reads those line by
    /// line either.
    static let mostComparisons = 20_000

    /// One row of the alignment: a pair, or a line with nothing opposite it.
    public struct Pair: Equatable, Sendable {
        /// Index into the removed lines, or nil where nothing was removed.
        public let old: Int?
        /// Index into the added lines, or nil where nothing was added.
        public let new: Int?

        public init(old: Int?, new: Int?) {
            self.old = old
            self.new = new
        }
    }

    /// Lines up a block of removals against a block of additions.
    ///
    /// The same shape as the word comparison one level down: a longest
    /// common subsequence, except that "common" means similar enough rather
    /// than identical. Order is kept, so a pair never reaches backwards past
    /// one already made.
    ///
    /// Lines that find no partner get a row to themselves rather than being
    /// packed against whatever was left over. The view grows taller for it,
    /// and in exchange nothing sits side by side that is not actually a
    /// before and after.
    public static func pairs(removed: [String], added: [String]) -> [Pair] {
        guard !removed.isEmpty else { return added.indices.map { Pair(old: nil, new: $0) } }
        guard !added.isEmpty else { return removed.indices.map { Pair(old: $0, new: nil) } }

        guard removed.count * added.count <= mostComparisons else {
            return byPosition(removed: removed.count, added: added.count)
        }

        // Each line is broken into words once, not once per candidate: the
        // loop below asks about every removal against every addition, and
        // tokenising inside it was what made a nine-hundred-line patch take
        // most of a second.
        let oldWords = removed.map(DiffWords.words(of:))
        let newWords = added.map(DiffWords.words(of:))

        let stride = added.count + 1
        var table = [Int](repeating: 0, count: (removed.count + 1) * stride)
        var alike = [Bool](repeating: false, count: removed.count * added.count)
        for i in Swift.stride(from: removed.count - 1, through: 0, by: -1) {
            for j in Swift.stride(from: added.count - 1, through: 0, by: -1) {
                let match = DiffWords.similarity(oldWords[i], newWords[j]) >= threshold
                alike[i * added.count + j] = match
                table[i * stride + j] = match
                    ? table[(i + 1) * stride + j + 1] + 1
                    : max(table[(i + 1) * stride + j], table[i * stride + j + 1])
            }
        }

        var result: [Pair] = []
        var oldAt = 0
        var newAt = 0
        while oldAt < removed.count || newAt < added.count {
            if oldAt < removed.count, newAt < added.count, alike[oldAt * added.count + newAt] {
                result.append(Pair(old: oldAt, new: newAt))
                oldAt += 1
                newAt += 1
                continue
            }

            // Unpaired lines come out removals first, which is the order the
            // patch itself writes them in.
            let takeOld = newAt == added.count
                || (oldAt < removed.count
                    && table[(oldAt + 1) * stride + newAt] >= table[oldAt * stride + newAt + 1])
            if takeOld {
                result.append(Pair(old: oldAt, new: nil))
                oldAt += 1
            } else {
                result.append(Pair(old: nil, new: newAt))
                newAt += 1
            }
        }
        return result
    }

    /// What the app did before there was an alignment: first with first.
    static func byPosition(removed: Int, added: Int) -> [Pair] {
        (0..<max(removed, added)).map {
            Pair(old: $0 < removed ? $0 : nil, new: $0 < added ? $0 : nil)
        }
    }

    /// The changed stretches of every line of a patch, in patch order.
    ///
    /// One entry per line, empty where the line is unchanged, unpaired, or
    /// not a line of code at all. Built here rather than in either view so
    /// that one column and two columns mark the same words.
    public static func emphasis(in patch: String) -> [[ChangedRange]] {
        let lines = patch.components(separatedBy: "\n")
        var result = Array(repeating: [ChangedRange](), count: lines.count)
        var index = 0

        while index < lines.count {
            guard isChange(lines[index]) else {
                index += 1
                continue
            }

            // The run of changed lines this one opens, which is as far as a
            // pairing may reach: a context line is an anchor, not a gap.
            var removed: [Int] = []
            var added: [Int] = []
            while index < lines.count, isChange(lines[index]) {
                if lines[index].hasPrefix("-") { removed.append(index) } else { added.append(index) }
                index += 1
            }

            let oldLines = removed.map { lines[$0] }
            let newLines = added.map { lines[$0] }
            for pair in pairs(removed: oldLines, added: newLines) {
                guard let old = pair.old, let new = pair.new else { continue }
                let comparison = DiffWords.compare(
                    DiffWords.words(of: oldLines[old]), DiffWords.words(of: newLines[new])
                )
                // A pair the alignment made by position rather than by
                // likeness is not a before and after, and marking the whole
                // of both lines would say it was.
                guard comparison.similarity >= threshold else { continue }
                result[removed[old]] = comparison.old
                result[added[new]] = comparison.new
            }
        }

        return result
    }

    static func isChange(_ line: String) -> Bool {
        (line.hasPrefix("+") || line.hasPrefix("-")) && !line.hasPrefix("---") && !line.hasPrefix("+++")
    }
}
