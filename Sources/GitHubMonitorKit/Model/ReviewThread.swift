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

    public init(
        id: String,
        path: String,
        line: Int?,
        side: Side,
        isResolved: Bool,
        isOutdated: Bool,
        comments: [IssueComment]
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.comments = comments
    }

    /// Whether the diff can show it where it was written.
    ///
    /// A thread with no line has nowhere to go in the patch. Guessing at
    /// the old number would put it beside whatever happens to be there now,
    /// which is worse than admitting it floats.
    public var isPlaceable: Bool { line != nil }

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
    /// reader does. Outdated ones never reach the patch and are left out
    /// here -- the file's header carries them.
    public static func placed(_ threads: [ReviewThread], in path: String) -> [ReviewThread] {
        threads
            .filter { $0.path == path && $0.isPlaceable && !$0.isOutdated }
            .sorted {
                $0.isResolved == $1.isResolved
                    ? ($0.line ?? 0, $0.id) < ($1.line ?? 0, $1.id)
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
            guard let line = thread.line else { return false }
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
    /// Outdated ones, and any GitHub declined to place. They are gathered
    /// at the file's header instead: a remark about code that has since
    /// been rewritten is often still the remark that mattered.
    public static func unplaceable(_ threads: [ReviewThread], in path: String) -> [ReviewThread] {
        threads
            .filter { $0.path == path && ($0.isOutdated || !$0.isPlaceable) }
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
