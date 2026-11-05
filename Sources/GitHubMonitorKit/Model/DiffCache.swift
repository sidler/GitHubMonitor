import Foundation

/// One line of a patch, worked out once.
///
/// What the view needs to draw a row and nothing it can derive cheaply:
/// where the line sits in both files, which of its words changed, and
/// whether it begins inside a block comment. All three depend on the
/// whole patch above it, which is why they are worked out together and
/// kept.
public struct PatchLine: Identifiable, Sendable {
    public let id: Int
    public let text: String
    /// Whether a `@@` has already gone by, which is what decides whether
    /// a leading `---` is furniture or code.
    public let insideHunk: Bool
    public let number: DiffLineNumber
    public let emphasis: [ChangedRange]
    /// Whether the line above left a block comment open.
    public let insideComment: Bool

    public init(
        id: Int,
        text: String,
        insideHunk: Bool,
        number: DiffLineNumber,
        emphasis: [ChangedRange],
        insideComment: Bool
    ) {
        self.id = id
        self.text = text
        self.insideHunk = insideHunk
        self.number = number
        self.emphasis = emphasis
        self.insideComment = insideComment
    }
}

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

    /// How much patch is worth holding on to, measured in the bytes of
    /// the patches themselves.
    ///
    /// Counted in bytes rather than in files, because a file is not a
    /// unit of anything. The bound used to be sixty-four files, and a
    /// pull request of sixty-eight small ones -- twenty lines each, the
    /// whole review barely sixty kilobytes -- walked straight past it.
    /// Every pass of the body evicted the files it was about to ask for
    /// again, so nothing was ever cached and the two-column alignment was
    /// worked out from scratch sixty-eight times a frame. Eighteen
    /// milliseconds a pass, against a frame of eight.
    ///
    /// Four megabytes of patch is more than ten reviews the size of the
    /// largest seen here, and the things derived from it are what the
    /// memory actually goes on.
    private let byteBudget = 4 * 1024 * 1024
    /// Never fewer than this, however large they are. The file being read
    /// has to survive whatever else is going on.
    private let floor = 8

    private var marks: [String: [[ChangedRange]]] = [:]
    private var rows: [String: [DiffSideRow]] = [:]
    private var numbers: [String: [DiffLineNumber]] = [:]
    private var comments: [String: (language: CodeLanguage?, state: DiffComments)] = [:]
    private var gaps: [String: (total: Int, found: [DiffGaps.Gap])] = [:]
    private var patchLines: [String: (language: CodeLanguage?, built: [PatchLine])] = [:]
    /// When each patch was last asked about, and how big it is.
    ///
    /// A clock rather than a queue. The queue was an array of patch
    /// *strings*, and keeping it in order meant `firstIndex(of:)` on
    /// every read -- a full string comparison against every patch held,
    /// on a path taken several times per file per frame.
    private var lastUsed: [String: UInt64] = [:]
    private var sizes: [String: Int] = [:]
    private var held = 0
    private var clock: UInt64 = 0

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
    /// Which line of which file each line of the patch is.
    ///
    /// Kept here with the rest: the unified layout asks for this three
    /// times in one pass of its body -- once for the lines, once for the
    /// width of the gutter and once more inside the thread anchoring --
    /// and the body runs again on every frame of a scroll.
    public func numbers(of patch: String) -> [DiffLineNumber] {
        if let known = numbers[patch] {
            remember(patch)
            return known
        }
        let worked = DiffLineNumbers.read(patch)
        numbers[patch] = worked
        remember(patch)
        return worked
    }

    /// The patch as a list of lines, each with its number, its marked
    /// words and whether it begins inside a block comment.
    ///
    /// The most-asked question of the lot: the view body builds this to
    /// drive its `ForEach`, and the body runs again whenever the pointer
    /// crosses a row. On a three-thousand-line patch that was three
    /// thousand structs and a string split every time.
    ///
    /// The language is held beside the answer rather than in the key, as
    /// it is for the comment scan this depends on: a patch belongs to one
    /// file and so to one language.
    public func lines(
        of patch: String, language: CodeLanguage?, build: () -> [PatchLine]
    ) -> [PatchLine] {
        if let known = patchLines[patch], known.language == language {
            remember(patch)
            return known.built
        }
        let worked = build()
        patchLines[patch] = (language, worked)
        remember(patch)
        return worked
    }

    /// Where the patch is silent, keyed by the patch and checked against
    /// the file's length.
    ///
    /// Here for the same reason the rest is: it reads the whole patch,
    /// and the body that asks runs again whenever the pointer crosses a
    /// row. Worked out afresh in a view body it would be the judder this
    /// cache was built to stop.
    ///
    /// The file's length is held beside the answer rather than made part
    /// of the key: a patch belongs to one file, and the length only
    /// changes when the file arrives.
    public func gaps(in patch: String, fileLines total: Int) -> [DiffGaps.Gap] {
        if let known = gaps[patch], known.total == total {
            remember(patch)
            return known.found
        }
        let worked = DiffGaps.gaps(in: patch, fileLines: total)
        gaps[patch] = (total, worked)
        remember(patch)
        return worked
    }

    /// Which of the patch's lines begin inside a block comment.
    ///
    /// Kept with the rest for the same reason: it is read inside a body
    /// that runs again on every frame of a scroll, and the answer depends
    /// on the whole patch above the line being drawn.
    ///
    /// The language is held alongside rather than made part of the key:
    /// a patch belongs to one file and so to one language, and a key of
    /// two parts would hold entries the sweep below could not find.
    public func comments(in patch: String, language: CodeLanguage?) -> DiffComments {
        if let known = comments[patch], known.language == language {
            remember(patch)
            return known.state
        }
        let worked = DiffComments.read(patch, language: language)
        comments[patch] = (language, worked)
        remember(patch)
        return worked
    }

    private func remember(_ patch: String) {
        clock &+= 1
        if lastUsed.updateValue(clock, forKey: patch) == nil {
            let size = patch.utf8.count
            sizes[patch] = size
            held += size
        }
        guard held > byteBudget, lastUsed.count > floor else { return }
        sweep()
    }

    /// Drops what has gone longest unread, in one go.
    ///
    /// In one go rather than one at a time: finding the oldest means
    /// looking at them all, and doing that per read is how the old queue
    /// came to cost what it did. Going a quarter under the budget buys
    /// that walk a few hundred reads of quiet.
    ///
    /// A review whose patches do not fit at all is the case this serves
    /// worst: priming works outwards from the file being read, so the
    /// least recently used are the ones nearest it. They are worked out
    /// again when scrolled to, which is where this stood before any of
    /// the priming -- so it is not a loss, only a budget nobody should
    /// have to reach.
    private func sweep() {
        let target = byteBudget - byteBudget / 4
        for (patch, _) in lastUsed.sorted(by: { $0.value < $1.value }) {
            guard held > target, lastUsed.count > floor else { return }
            forget(patch)
        }
    }

    private func forget(_ patch: String) {
        held -= sizes.removeValue(forKey: patch) ?? 0
        lastUsed[patch] = nil
        marks[patch] = nil
        rows[patch] = nil
        numbers[patch] = nil
        comments[patch] = nil
        gaps[patch] = nil
        patchLines[patch] = nil
    }

    /// How many patches are being held, for the test that the bound holds.
    var count: Int { lastUsed.count }

    /// How much patch is being held, for the same test.
    var bytesHeld: Int { held }

    /// The bound itself, so a test can fill past it without naming a
    /// number of its own.
    var budget: Int { byteBudget }

    /// Works out everything a diff will ask for, off the main thread,
    /// before the scroll gets there.
    ///
    /// The work itself is unavoidable: a word-level diff and, in two
    /// columns, the pairing of removals with the additions answering
    /// them. On a pull request of fifty-three files it comes to about
    /// three quarters of a second -- and it was paid a file at a time, on
    /// the main thread, as each one scrolled into view. One file of
    /// fifteen hundred patch lines cost a tenth of a second in a single
    /// frame, which is a stall you can see.
    ///
    /// The file being read comes first and the rest follow outwards, so
    /// what somebody is looking at is ready before what they might scroll
    /// to. Cancelled when the diff closes: there is no point finishing
    /// the work for a window that has gone.
    func prime(
        _ patches: [(patch: String, language: CodeLanguage?)], from index: Int = 0
    ) -> Task<Void, Never> {
        let ordered = Self.outwards(from: index, count: patches.count).map { patches[$0] }
        return Task.detached(priority: .utility) {
            for entry in ordered {
                if Task.isCancelled { return }
                // Worked out here, off the main thread, and only handed
                // over once it is done.
                let numbers = DiffLineNumbers.read(entry.patch)
                let marks = DiffAlignment.emphasis(in: entry.patch)
                let sides = DiffSideBySide.rows(of: entry.patch)
                let comments = DiffComments.read(entry.patch, language: entry.language)
                if Task.isCancelled { return }
                await MainActor.run {
                    DiffCache.shared.store(
                        entry.patch, language: entry.language,
                        numbers: numbers, marks: marks, sides: sides, comments: comments
                    )
                }
            }
        }
    }

    /// The order to work through: the one being read, then its
    /// neighbours, then theirs.
    static func outwards(from index: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let start = min(max(0, index), count - 1)
        var order = [start]
        var step = 1
        while order.count < count {
            if start - step >= 0 { order.append(start - step) }
            if start + step < count { order.append(start + step) }
            step += 1
        }
        return order
    }

    /// Takes what was worked out elsewhere. Anything already here was
    /// asked for while this was in flight and is the same answer.
    func store(
        _ patch: String,
        language: CodeLanguage?,
        numbers: [DiffLineNumber],
        marks: [[ChangedRange]],
        sides: [DiffSideRow],
        comments: DiffComments
    ) {
        if self.numbers[patch] == nil { self.numbers[patch] = numbers }
        if self.marks[patch] == nil { self.marks[patch] = marks }
        if rows[patch] == nil { rows[patch] = sides }
        if self.comments[patch] == nil { self.comments[patch] = (language, comments) }
        remember(patch)
    }

    /// For tests, which must not read what another test left behind.
    func forget() {
        numbers.removeAll()
        marks = [:]
        rows = [:]
        comments = [:]
        gaps = [:]
        patchLines = [:]
        lastUsed = [:]
        sizes = [:]
        held = 0
    }
}
