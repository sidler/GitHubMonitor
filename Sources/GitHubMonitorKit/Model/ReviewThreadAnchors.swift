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
    /// Handed the line numbers rather than the patch, so that whoever
    /// calls it decides where they come from.
    ///
    /// They used to be read here, from the patch, on every call -- and
    /// this is the one piece of a patch's arithmetic that runs only when
    /// somebody has commented on it, which is why a file with a
    /// conversation on it scrolled worse than the same file without.
    /// Reading the numbers of a nine-hundred-line patch costs a third of
    /// a millisecond and the view's body is evaluated again whenever the
    /// pointer crosses a row; the cache answers in a fiftieth of that.
    public static func unified(
        numbers: [DiffLineNumber], threads: [ReviewThread]
    ) -> [Int: [ReviewThread]] {
        var anchors: [Int: [ReviewThread]] = [:]
        for (index, place) in numbers.enumerated() {
            let here = ReviewThreadPlacement.on(place, from: threads)
            if !here.isEmpty { anchors[index] = here }
        }
        for (index, adrift) in ReviewThreadPlacement.near(threads, over: numbers) {
            anchors[index, default: []] += adrift
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
        // One entry per row, so an index into this is an index into the
        // rows -- including the ones that are not a pair, which carry no
        // numbers and so can never be the nearest line to anything.
        var places: [DiffLineNumber] = []
        for (index, row) in rows.enumerated() {
            guard case .pair(let left, let right) = row else {
                places.append(.none)
                continue
            }
            places.append(DiffLineNumber(old: left?.number, new: right?.number))
            var here = ReviewThreadPlacement.on(
                DiffLineNumber(old: nil, new: right?.number), side: .new, from: threads
            )
            here += ReviewThreadPlacement.on(
                DiffLineNumber(old: left?.number, new: nil), side: .old, from: threads
            )
            if !here.isEmpty { anchors[index] = here }
        }
        for (index, adrift) in ReviewThreadPlacement.near(threads, over: places) {
            anchors[index, default: []] += adrift
        }
        return anchors
    }

}
