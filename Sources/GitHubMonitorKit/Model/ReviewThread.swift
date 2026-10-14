import Foundation

/// A conversation hanging off one line of a pull request's diff.
///
/// Threads rather than loose comments, because that is what GitHub makes of
/// them: a remark and the replies to it belong together, are resolved
/// together, and reading the first without the second is how an argument
/// gets had twice.
public struct ReviewThread: Identifiable, Hashable, Sendable {
    /// Which file of the diff the thread hangs in.
    public enum Side: String, Hashable, Sendable {
        /// The file as it was. A comment on a removed line.
        case old
        /// The file as it will be. Nearly all of them.
        case new

        init(apiValue: String?) {
            self = apiValue == "LEFT" ? .old : .new
        }
    }

    public let id: String
    public let path: String
    /// The line it hangs on, in the file its side names.
    ///
    /// Nil where GitHub no longer places it: the line it was written
    /// against has since gone, which is also what `isOutdated` says.
    public let line: Int?
    public let side: Side
    public let isResolved: Bool
    public let isOutdated: Bool
    public let comments: [IssueComment]

    /// Where it was written, in the file as it stood then.
    ///
    /// GitHub keeps this after it has given up on `line`, which it does
    /// once the code has moved. It is the only thing left that says where
    /// in the file the remark belongs -- but it counts in a version of
    /// the file this patch does not carry, so it places a thread roughly
    /// and never exactly. See `hunk` for what makes up the difference.
    public let originalLine: Int?

    /// The few lines the remark was written against, as GitHub stored
    /// them with the first comment.
    ///
    /// This is what lets an outdated thread stand anywhere at all: the
    /// code it is about travels with it, so it does not matter that the
    /// line beside it today is somebody else's.
    public let hunk: String?

    public init(
        id: String,
        path: String,
        line: Int?,
        side: Side,
        isResolved: Bool,
        isOutdated: Bool,
        comments: [IssueComment],
        originalLine: Int? = nil,
        hunk: String? = nil
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.comments = comments
        self.originalLine = originalLine
        self.hunk = hunk
    }

    /// Whether the diff can show it at all.
    ///
    /// Either number will do. A thread with neither has nowhere to go and
    /// is gathered at the file's header instead.
    public var isPlaceable: Bool { line != nil || originalLine != nil }

    /// Whether it has to be put somewhere near rather than somewhere
    /// exact, which is also when its own lines of code are worth drawing.
    public var isAdrift: Bool { line == nil && originalLine != nil }

    /// The line to hang it on, whichever of the two is left.
    public var anchorLine: Int? { line ?? originalLine }

    /// The tail of the stored hunk: the lines just before the one the
    /// remark is about, and that line last.
    ///
    /// The tail rather than the whole thing, because GitHub cuts a hunk
    /// so that it ends on the line being commented on, and the start of
    /// it can run thirty lines back. Four is enough to recognise the
    /// place without turning a remark into a second diff.
    public func context(limit: Int = 4) -> [String] {
        guard let hunk, !hunk.isEmpty else { return [] }
        let lines = hunk
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            // The @@ header says which lines these were in a file nobody
            // is looking at any more, and it is the first thing to go
            // when there is room for four lines and not five.
            .filter { !$0.hasPrefix("@@") }
        guard !lines.isEmpty else { return [] }
        return Array(lines.suffix(limit))
    }

    /// What the collapsed form says, for a thread that is resolved.
    public var summary: String {
        let count = comments.count
        let what = count == 1 ? "1 comment" : "\(count) comments"
        return isOutdated ? "\(what), outdated" : "\(what), resolved"
    }
}

/// Which threads belong where in a drawn patch.
public enum ReviewThreadPlacement {
    /// The threads of one file, in the order they should be read.
    ///
    /// Unresolved first, because those are the ones asking for something;
    /// within each group by line, so they run down the file the way the
    /// reader does.
    ///
    /// Outdated ones are in here now. They used to be sent to the file's
    /// header, which read as a pile of things nobody could place -- and
    /// since a remark is usually resolved by changing the code, which is
    /// what makes GitHub drop its line, that pile was most of the review.
    /// They are placed by the line they were written against and carry
    /// their own few lines of code to say what that line held.
    public static func placed(_ threads: [ReviewThread], in path: String) -> [ReviewThread] {
        threads
            .filter { $0.path == path && $0.isPlaceable }
            .sorted {
                $0.isResolved == $1.isResolved
                    ? ($0.anchorLine ?? 0, $0.id) < ($1.anchorLine ?? 0, $1.id)
                    : !$0.isResolved
            }
    }

    /// The threads of one file the patch can actually show, in the order
    /// they should be read.
    ///
    /// The patch is asked, not assumed. A review of a large file arrives
    /// with the hunks GitHub chose to send, and a remark on a line outside
    /// them has no row to hang on -- handed to the view it was passed over
    /// in silence, counted in the list beside the diff and drawn nowhere.
    @MainActor
    public static func placed(
        _ threads: [ReviewThread], in path: String, patch: String
    ) -> [ReviewThread] {
        let shown = lines(of: patch)
        return placed(threads, in: path).filter { thread in
            // One that still has a line of its own has to be on a line
            // the patch carries. One adrift is put near rather than on,
            // so all the patch has to have is somewhere to put it -- but
            // it does have to have that, or the thread would be counted
            // beside the diff and drawn nowhere.
            guard let line = thread.line else { return thread.isAdrift && !shown.isEmpty }
            return shown.contains(ThreadLine(side: thread.side, number: line))
        }
    }

    /// The threads of one file that have nowhere to go in its patch:
    /// outdated, unplaced by GitHub, or written against a line the patch
    /// does not carry.
    @MainActor
    public static func stranded(
        _ threads: [ReviewThread], in path: String, patch: String
    ) -> [ReviewThread] {
        let drawn = Set(placed(threads, in: path, patch: patch).map(\.id))
        return threads
            .filter { $0.path == path && !drawn.contains($0.id) }
            .sorted { ($0.line ?? 0, $0.id) < ($1.line ?? 0, $1.id) }
    }

    /// The threads of one file, with the settled ones left out unless
    /// somebody asked for them.
    ///
    /// Resolved only, and the distinction is the whole point. A remark
    /// about code that has since been rewritten but that nobody ever
    /// answered is still an open question -- it only looks like history.
    /// Those stay wherever they are, whatever this is set to.
    public static func asked(
        _ threads: [ReviewThread], in path: String, showingResolved: Bool
    ) -> [ReviewThread] {
        threads.filter { $0.path == path && (showingResolved || !$0.isResolved) }
    }

    /// How many conversations on one file have been settled, for the
    /// control that puts them away and says how many it is hiding.
    public static func settled(_ threads: [ReviewThread], in path: String) -> Int {
        threads.count { $0.path == path && $0.isResolved }
    }

    /// Where the threads go that GitHub no longer gives a line for.
    ///
    /// The row named is the last one at or before the line the remark was
    /// written against, so it lands after the code it followed rather
    /// than at the top of the file. Approximate on purpose: that number
    /// counts in a version of the file this patch does not carry, and no
    /// arithmetic will turn it into a line that is really here. What
    /// makes it honest is that the thread brings its own lines of code
    /// with it -- the reader is told what the remark was about rather
    /// than left to assume it was about whatever is next to it.
    ///
    /// Before the first numbered row where it belongs above everything,
    /// since a remark about line four of a file whose patch starts at
    /// line ninety still belongs at the top of what is shown.
    public static func near(
        _ threads: [ReviewThread], over places: [DiffLineNumber]
    ) -> [Int: [ReviewThread]] {
        guard !places.isEmpty else { return [:] }
        var anchors: [Int: [ReviewThread]] = [:]
        for thread in threads where thread.isAdrift {
            guard let wanted = thread.originalLine else { continue }
            var landed: Int?
            for (index, place) in places.enumerated() {
                guard let number = thread.side == .new ? place.new : place.old else { continue }
                if number <= wanted { landed = index }
            }
            anchors[landed ?? 0, default: []].append(thread)
        }
        return anchors
    }

    /// One line of one of the two files.
    private struct ThreadLine: Hashable {
        let side: ReviewThread.Side
        let number: Int
    }

    /// Which lines of which file the patch actually carries.
    @MainActor
    private static func lines(of patch: String) -> Set<ThreadLine> {
        var result: Set<ThreadLine> = []
        for place in DiffCache.shared.numbers(of: patch) {
            if let old = place.old { result.insert(ThreadLine(side: .old, number: old)) }
            if let new = place.new { result.insert(ThreadLine(side: .new, number: new)) }
        }
        return result
    }

    /// The threads of one file that the patch cannot hold.
    ///
    /// The ones GitHub gives no number for at all, in either file. They
    /// are gathered at the file's header: a remark nobody can place is
    /// still often the remark that mattered. Outdated ones no longer come
    /// here -- they keep the line they were written against.
    public static func unplaceable(_ threads: [ReviewThread], in path: String) -> [ReviewThread] {
        threads
            .filter { $0.path == path && !$0.isPlaceable }
            .sorted { ($0.line ?? 0, $0.id) < ($1.line ?? 0, $1.id) }
    }

    /// What a file holds, for the list beside the diff.
    public struct OpenComments: Equatable, Sendable {
        /// Conversations nobody has resolved.
        public let conversations: Int
        /// Every conversation on the file, resolved ones included.
        ///
        /// Both numbers because one of them alone misleads. Only the open
        /// ones, and the list says 1 where the diff draws four. Only the
        /// total, and a file whose remarks have all been dealt with looks
        /// like one nobody has touched.
        public let total: Int
        /// The remarks those hold, which is a different number as soon as
        /// anybody replies.
        public let comments: Int

        public init(conversations: Int, total: Int, comments: Int) {
            self.conversations = conversations
            self.total = total
            self.comments = comments
        }

        /// What the badge says: `1` where everything open is everything
        /// there is, `1/4` where it is not.
        public var text: String {
            conversations == total ? "\(total)" : "\(conversations)/\(total)"
        }

        /// Spelled out, because a bare number beside a file name could be
        /// any of the three.
        public var label: String {
            let threads = conversations == 1
                ? "1 open conversation" : "\(conversations) open conversations"
            let all = total == conversations
                ? "" : total == 1 ? " of 1" : " of \(total)"
            let remarks = comments == 1 ? "1 comment" : "\(comments) comments"
            return "\(threads)\(all), \(remarks)"
        }
    }

    /// How much each file still has open, by path.
    ///
    /// Counted by conversation rather than by comment: five replies
    /// arguing one point are one thing to deal with, and a list that said
    /// "5" would send somebody looking for five of them. The comment count
    /// is kept for the tooltip, where there is room to say both.
    ///
    /// Outdated conversations count. GitHub cannot place them any more, so
    /// they are gathered at the file's header rather than in its patch --
    /// but unresolved is unresolved, and a file whose list entry said
    /// nothing would be a file nobody opens again.
    ///
    /// Resolved ones count towards the total, because the diff draws them:
    /// a list saying 1 beside a file showing four conversations is a list
    /// nobody can trust.
    public static func openCounts(_ threads: [ReviewThread]) -> [String: OpenComments] {
        var counts: [String: (conversations: Int, total: Int, comments: Int)] = [:]
        for thread in threads {
            counts[thread.path, default: (0, 0, 0)].total += 1
            guard !thread.isResolved else { continue }
            counts[thread.path, default: (0, 0, 0)].conversations += 1
            counts[thread.path, default: (0, 0, 0)].comments += thread.comments.count
        }
        return counts.mapValues {
            OpenComments(
                conversations: $0.conversations, total: $0.total, comments: $0.comments
            )
        }
    }

    /// The threads hanging on one line of a file, given that line's numbers
    /// in the old and the new file.
    ///
    /// Matched on the number rather than on a position in the patch:
    /// GitHub counts in the file, the patch counts in itself, and a thread
    /// placed by patch offset lands somewhere different in every hunk.
    public static func on(
        _ place: DiffLineNumber, side: ReviewThread.Side? = nil, from threads: [ReviewThread]
    ) -> [ReviewThread] {
        threads.filter { thread in
            guard let line = thread.line else { return false }
            if let side, thread.side != side { return false }
            return thread.side == .new ? line == place.new : line == place.old
        }
    }
}
