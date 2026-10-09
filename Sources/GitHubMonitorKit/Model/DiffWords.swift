import Foundation

/// A stretch of a line that changed, in characters from the line's start.
///
/// Offsets into the whole line, marker column included, because that is what
/// the view draws. The comparison itself ignores the marker.
public struct ChangedRange: Hashable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    var end: Int { location + length }
}

/// What two versions of one line have in common, and where they differ.
public struct LineComparison: Equatable, Sendable {
    /// The stretches of the old line that are not in the new one.
    public let old: [ChangedRange]
    /// The stretches of the new line that are not in the old one.
    public let new: [ChangedRange]
    /// Between 0 and 1, over everything that is not whitespace.
    public let similarity: Double
}

/// A line broken into words, ready to be compared against many others.
///
/// Kept rather than worked out each time: the alignment one level up asks
/// how alike every removal is to every addition, and tokenising both sides
/// inside that loop meant forty thousand passes over a patch that has nine
/// hundred lines in it. Once per line is enough.
public struct LineWords: Sendable {
    /// Every token in order, whitespace included, for finding the ranges.
    let tokens: [Substring]
    /// How often each word appears, whitespace left out, for the score.
    let counts: [Substring: Int]
    /// How many tokens that dictionary stands for.
    let weight: Int
    /// Where the line's body begins, since the marker column is not part of
    /// the comparison but the ranges are reported against the whole line.
    let offset: Int
    /// True where the line was too long to look at word by word.
    let isTooLong: Bool
    let body: Substring
}

/// Compares two versions of a line word by word.
///
/// A diff says a line changed; it does not say what about it changed. On a
/// line where one identifier was renamed that is the whole content of the
/// change, and finding it by eye means reading two nearly identical lines
/// character by character -- which is exactly the work a diff is supposed to
/// have already done.
///
/// Word by word rather than character by character: `getUser` next to
/// `getUsers` differs in one letter, and marking that letter alone is
/// precise and useless. The word is the unit the reader thinks in.
public enum DiffWords {
    /// Letters, digits and `_` run together; whitespace runs together; every
    /// other character stands alone.
    ///
    /// Punctuation on its own is what keeps `$row['id']` from being one
    /// word: with it, only `id` is marked when it becomes `login`. Grouping
    /// by whitespace instead would paint half the expression.
    static func tokens(_ line: Substring) -> [Substring] {
        var tokens: [Substring] = []
        var index = line.startIndex

        while index < line.endIndex {
            let start = index
            let character = line[index]

            if character.isWhitespace {
                while index < line.endIndex, line[index].isWhitespace {
                    index = line.index(after: index)
                }
            } else if Self.isWord(character) {
                while index < line.endIndex, Self.isWord(line[index]) {
                    index = line.index(after: index)
                }
            } else {
                index = line.index(after: index)
            }

            tokens.append(line[start..<index])
        }

        return tokens
    }

    static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// The marker column a unified diff puts at the start of every line.
    ///
    /// Dropped before comparing: with it in, no removal is ever equal to any
    /// addition, every line looks different in its first character, and that
    /// character is marked on every line of the file.
    static func body(of line: String) -> Substring {
        guard let first = line.first, first == "+" || first == "-" || first == " " else {
            return line[...]
        }
        return line.dropFirst()
    }

    /// A line split into its marker column and the code after it, with the
    /// marked stretches moved to match.
    ///
    /// Drawn apart because a wrapped line has to be told from a new one.
    /// With the marker in the text, the second half of a long line starts
    /// where a `+` or `-` would be and reads as a line of its own -- the
    /// confusion a diff exists to prevent. In its own column the marker
    /// cannot be mistaken for anything, and what wraps lines up under the
    /// code it belongs to.
    public static func split(
        _ line: String, emphasis: [ChangedRange] = []
    ) -> (marker: String, body: String, emphasis: [ChangedRange]) {
        let body = body(of: line)
        let offset = line.count - body.count
        guard offset > 0 else { return ("", line, emphasis) }

        let moved = emphasis.compactMap { range -> ChangedRange? in
            let start = max(0, range.location - offset)
            let length = range.length - max(0, offset - range.location)
            guard length > 0 else { return nil }
            return ChangedRange(location: start, length: length)
        }
        return (String(line.prefix(offset)), String(body), moved)
    }

    /// Lines longer than this are compared by length alone.
    ///
    /// The marking is quadratic in the number of words. A minified bundle on
    /// one line would otherwise stop the window while it is worked out, and
    /// nobody reads a minified line word by word anyway.
    static let longestComparable = 600

    public static func words(of line: String) -> LineWords {
        let body = body(of: line)
        let offset = line.count - body.count

        guard body.count <= longestComparable else {
            return LineWords(
                tokens: [], counts: [:], weight: 0,
                offset: offset, isTooLong: true, body: body
            )
        }

        let tokens = tokens(body)
        var counts: [Substring: Int] = [:]
        var weight = 0
        for token in tokens where !token.allSatisfy(\.isWhitespace) {
            counts[token, default: 0] += 1
            weight += 1
        }

        return LineWords(
            tokens: tokens, counts: counts, weight: weight,
            offset: offset, isTooLong: false, body: body
        )
    }

    /// How alike two lines are, between 0 and 1.
    ///
    /// Counted over words rather than worked out from the longest common
    /// subsequence, which is the same thing this file does one level down
    /// and far more expensive: the alignment asks this of every removal
    /// against every addition in a block.
    ///
    /// Order is not part of it. `$a = $b` and `$b = $a` score as identical,
    /// which for deciding "are these the same line, edited" is the right
    /// answer anyway.
    ///
    /// Whitespace is left out. Indentation would otherwise make every pair
    /// of deeply nested lines look alike: two unrelated statements eight
    /// levels in share eight spaces and little else.
    public static func similarity(_ old: LineWords, _ new: LineWords) -> Double {
        guard !old.isTooLong, !new.isTooLong else { return old.body == new.body ? 1 : 0 }
        // Two lines of nothing but whitespace are the same line as far as
        // anybody reading them is concerned.
        guard old.weight + new.weight > 0 else { return 1 }

        // The multiset overlap, counted from the smaller side: a word shared
        // n times by one and m times by the other is shared min(n, m) times.
        let (fewer, more) = old.counts.count <= new.counts.count
            ? (old.counts, new.counts)
            : (new.counts, old.counts)
        var shared = 0
        for (word, count) in fewer {
            shared += min(count, more[word] ?? 0)
        }

        return 2 * Double(shared) / Double(old.weight + new.weight)
    }

    public static func similarity(_ old: String, _ new: String) -> Double {
        similarity(words(of: old), words(of: new))
    }

    public static func compare(_ old: String, _ new: String) -> LineComparison {
        compare(words(of: old), words(of: new))
    }

    public static func compare(_ old: LineWords, _ new: LineWords) -> LineComparison {
        let score = similarity(old, new)
        guard !old.isTooLong, !new.isTooLong else {
            return LineComparison(old: [], new: [], similarity: score)
        }

        let table = CommonTable(old.tokens, new.tokens)
        var oldChanged: [ChangedRange] = []
        var newChanged: [ChangedRange] = []
        var oldAt = 0
        var newAt = 0
        var oldPosition = old.offset
        var newPosition = new.offset

        // Walking forwards through the table rather than backtracking from
        // the end, so the ranges come out in the order they are drawn.
        while oldAt < old.tokens.count || newAt < new.tokens.count {
            if oldAt < old.tokens.count, newAt < new.tokens.count,
               old.tokens[oldAt] == new.tokens[newAt]
            {
                oldPosition += old.tokens[oldAt].count
                newPosition += new.tokens[newAt].count
                oldAt += 1
                newAt += 1
                continue
            }

            // Follow whichever side the table says keeps more in common.
            let takeOld = newAt == new.tokens.count
                || (oldAt < old.tokens.count
                    && table.common(oldAt + 1, newAt) >= table.common(oldAt, newAt + 1))
            if takeOld {
                append(ChangedRange(
                    location: oldPosition, length: old.tokens[oldAt].count
                ), to: &oldChanged)
                oldPosition += old.tokens[oldAt].count
                oldAt += 1
            } else {
                append(ChangedRange(
                    location: newPosition, length: new.tokens[newAt].count
                ), to: &newChanged)
                newPosition += new.tokens[newAt].count
                newAt += 1
            }
        }

        return LineComparison(old: oldChanged, new: newChanged, similarity: score)
    }

    /// Keeps the ranges apart only where there is something between them, so
    /// a renamed call does not come out as four separate marks.
    private static func append(_ range: ChangedRange, to ranges: inout [ChangedRange]) {
        if let last = ranges.last, last.end == range.location {
            ranges[ranges.count - 1] = ChangedRange(
                location: last.location, length: last.length + range.length
            )
            return
        }
        ranges.append(range)
    }

    /// How many tokens the tails of the two lines share, for every pair of
    /// starting points.
    ///
    /// One flat array rather than an array of arrays: the table is built
    /// once per marked pair, and a column of separately allocated rows costs
    /// more in allocation than the comparison does in arithmetic.
    struct CommonTable {
        private let stride: Int
        private var cells: [Int]

        init(_ old: [Substring], _ new: [Substring]) {
            stride = new.count + 1
            cells = Array(repeating: 0, count: (old.count + 1) * stride)
            for i in Swift.stride(from: old.count - 1, through: 0, by: -1) {
                for j in Swift.stride(from: new.count - 1, through: 0, by: -1) {
                    cells[i * stride + j] = old[i] == new[j]
                        ? cells[(i + 1) * stride + j + 1] + 1
                        : max(cells[(i + 1) * stride + j], cells[i * stride + j + 1])
                }
            }
        }

        func common(_ i: Int, _ j: Int) -> Int { cells[i * stride + j] }
    }
}
