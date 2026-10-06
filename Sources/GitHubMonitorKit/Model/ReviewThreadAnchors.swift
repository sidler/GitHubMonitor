import Foundation

/// Which of a file's drawn lines each conversation hangs off.
///
/// Matched on the file's line numbers rather than on a position in the
/// patch: GitHub counts in the file, the patch counts in itself, and a
/// thread placed by patch offset lands somewhere different in every hunk.
public enum ReviewThreadAnchors {
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

}
