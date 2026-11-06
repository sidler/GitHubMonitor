import Foundation

/// One move between draft and ready.
public struct DraftChange: Hashable, Sendable, Codable {
    public let at: Date
    /// True where this put the pull request back into draft, false where it
    /// made it ready for review.
    public let toDraft: Bool

    public init(at: Date, toDraft: Bool) {
        self.at = at
        self.toDraft = toDraft
    }
}

/// A pull request as the backlog chart needs it: when it appeared, when it
/// went away, and when it was a draft.
///
/// The whole history rather than today's state, because the chart asks what
/// was open at the end of each of twelve periods. GitHub's search can only
/// answer that about now -- `is:draft` is a flag, not a date -- so the
/// events that moved it are fetched and replayed instead. Counting today's
/// drafts backwards would have shown a draft pile that grows towards the
/// present purely because the older ones have since been marked ready.
public struct BacklogPullRequest: Hashable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    /// Opened by a bot account, so the chart's "include bots" switch can
    /// leave it out without another fetch.
    public let isBot: Bool
    public let createdAt: Date
    /// Nil while it is still open.
    public let closedAt: Date?
    /// Whether it is a draft now -- the state after the last change below.
    public let isDraft: Bool
    /// Every move between draft and ready, oldest first.
    public let draftChanges: [DraftChange]

    public init(
        key: String,
        isBot: Bool,
        createdAt: Date,
        closedAt: Date?,
        isDraft: Bool,
        draftChanges: [DraftChange] = []
    ) {
        self.key = key
        self.isBot = isBot
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.isDraft = isDraft
        self.draftChanges = draftChanges.sorted { $0.at < $1.at }
    }

    /// Open at that moment: created by then and not closed yet.
    ///
    /// The close is exclusive -- a pull request closed at the stroke of the
    /// period's end was not part of the backlog it left behind.
    public func wasOpen(at moment: Date) -> Bool {
        guard createdAt <= moment else { return false }
        guard let closedAt else { return true }
        return closedAt > moment
    }

    /// Draft at that moment, whatever it is now.
    ///
    /// The last change on or before the moment decides it. Before the first
    /// change, the state was the opposite of what that change produced: a
    /// pull request whose first event marked it ready had been a draft until
    /// then. With no changes at all, it has always been what it is now.
    public func wasDraft(at moment: Date) -> Bool {
        if let last = draftChanges.last(where: { $0.at <= moment }) { return last.toDraft }
        if let first = draftChanges.first { return !first.toDraft }
        return isDraft
    }
}

/// How many pull requests stood open at a given moment.
public enum BacklogMath {
    /// Open and, of those, still drafts.
    ///
    /// Drafts are counted inside the open total rather than beside it: a
    /// draft is an open pull request, and two lines that add up to more than
    /// the repository has would be read as a third number nobody meant.
    public static func count(
        _ pullRequests: [BacklogPullRequest],
        at moment: Date
    ) -> (open: Int, draft: Int) {
        var open = 0
        var draft = 0
        for pullRequest in pullRequests where pullRequest.wasOpen(at: moment) {
            open += 1
            if pullRequest.wasDraft(at: moment) { draft += 1 }
        }
        return (open, draft)
    }
}
