import Foundation

/// Remembers what was worked out about a patch, so scrolling does not pay
/// for it again.
///
/// Both of the things kept here are read inside a view's `body`, which SwiftUI
/// runs again whenever anything it watches moves -- and scrolling moves the
/// file at the top of the column on every frame. Working out the alignment of
/// a nine-hundred-line patch takes some tens of milliseconds, which is nothing
/// once and far too much sixty times a second.
///
/// Keyed by the patch itself rather than by the file's path: a patch is
/// immutable once fetched, two files with the same contents give the same
/// answer, and nothing has to be told when a diff is closed.
@MainActor
public final class DiffCache {
    public static let shared = DiffCache()

    /// A pull request can touch hundreds of files; this is about how many
    /// anybody scrolls past in one sitting. Past it the oldest goes.
    private let limit = 64

    private var marks: [String: [[ChangedRange]]] = [:]
    private var rows: [String: [DiffSideRow]] = [:]
    private var order: [String] = []

    public func emphasis(in patch: String) -> [[ChangedRange]] {
        if let known = marks[patch] {
            remember(patch)
            return known
        }
        let worked = DiffAlignment.emphasis(in: patch)
        marks[patch] = worked
        remember(patch)
        return worked
    }

    public func rows(of patch: String) -> [DiffSideRow] {
        if let known = rows[patch] {
            remember(patch)
            return known
        }
        let worked = DiffSideBySide.rows(of: patch)
        rows[patch] = worked
        remember(patch)
        return worked
    }

    /// Moves a patch to the front of the queue, whether it was just worked
    /// out or just read.
    ///
    /// On reading too, which it did not do before: both hit paths returned
    /// before reaching here, so the order was the order patches first
    /// arrived and the oldest was dropped however often it was being read.
    /// In a review of more than sixty-four files that meant the file at the
    /// top of the column -- read on every frame -- was thrown out to make
    /// room for one being scrolled past.
    private func remember(_ patch: String) {
        if let seen = order.firstIndex(of: patch) { order.remove(at: seen) }
        order.append(patch)
        while order.count > limit {
            let oldest = order.removeFirst()
            marks[oldest] = nil
            rows[oldest] = nil
        }
    }

    /// How many patches are being held, for the test that the bound holds.
    var count: Int { order.count }

    /// For tests, which must not read what another test left behind.
    func forget() {
        marks = [:]
        rows = [:]
        order = []
    }
}
