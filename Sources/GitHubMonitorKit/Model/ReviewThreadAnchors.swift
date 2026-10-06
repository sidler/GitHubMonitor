import Foundation

/// Where a file's conversations sit among its drawn lines, and how the
/// patch is cut up to make room for them.
///
/// Cut rather than drawn inside: a comment is prose and the patch scrolls
/// sideways. A thread inside that scroll would travel off the edge with a
/// long line of code, which is not where anybody left it.
public enum ReviewThreadAnchors {
    /// A stretch of patch, or a place where conversations interrupt it.
    public enum Segment: Identifiable, Equatable, Sendable {
        /// Rows to draw, as indices into whatever the layout produced.
        case code(Range<Int>)
        /// The conversations hanging off the row just above.
        case threads([ReviewThread])

        public var id: String {
            switch self {
            case .code(let range): "code-\(range.lowerBound)-\(range.upperBound)"
            case .threads(let threads): "threads-\(threads.first?.id ?? "none")"
            }
        }
    }

    /// Which threads hang off each line of a patch drawn in one column.
    ///
    /// Keyed by the line's place in the patch, which is what the view
    /// counts in; the matching itself is on the file's line numbers, which
    /// is what GitHub counts in.
    public static func unified(
        patch: String, threads: [ReviewThread]
    ) -> [Int: [ReviewThread]] {
        let numbers = DiffLineNumbers.read(patch)
        var anchors: [Int: [ReviewThread]] = [:]
        for (index, place) in numbers.enumerated() {
            let here = ReviewThreadPlacement.on(place, from: threads)
            if !here.isEmpty { anchors[index] = here }
        }
        return anchors
    }

    /// The same, for a patch drawn in two columns.
    ///
    /// A thread belongs to a row rather than to a column: it was written
    /// about one line, and that line is on one side or the other.
    public static func sideBySide(
        rows: [DiffSideRow], threads: [ReviewThread]
    ) -> [Int: [ReviewThread]] {
        var anchors: [Int: [ReviewThread]] = [:]
        for (index, row) in rows.enumerated() {
            guard case .pair(let left, let right) = row else { continue }
            var here = ReviewThreadPlacement.on(
                DiffLineNumber(old: nil, new: right?.number), side: .new, from: threads
            )
            here += ReviewThreadPlacement.on(
                DiffLineNumber(old: left?.number, new: nil), side: .old, from: threads
            )
            if !here.isEmpty { anchors[index] = here }
        }
        return anchors
    }

    /// Cuts `0..<count` rows into stretches of patch with the threads
    /// between them.
    ///
    /// Each thread stop comes after the row it hangs on, which is how a
    /// remark reads: the line, then what was said about it.
    public static func segments(
        count: Int, anchors: [Int: [ReviewThread]]
    ) -> [Segment] {
        guard !anchors.isEmpty else {
            return count > 0 ? [.code(0..<count)] : []
        }

        var segments: [Segment] = []
        var start = 0
        for index in anchors.keys.sorted() {
            guard index < count else { continue }
            segments.append(.code(start..<(index + 1)))
            segments.append(.threads(anchors[index] ?? []))
            start = index + 1
        }
        if start < count { segments.append(.code(start..<count)) }
        return segments
    }
}
