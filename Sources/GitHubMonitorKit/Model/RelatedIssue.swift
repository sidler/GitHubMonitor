import Foundation

/// One issue named in another's family: a child filed under it, or the
/// parent it sits under.
///
/// GitHub's own relation, not a number read out of prose: an issue is put
/// under a parent deliberately, which is what makes a count of them worth
/// drawing as progress. The looser links -- "closes #4711", a number in a
/// sentence -- are what `ItemLink` is for, and mixing the two would put a
/// passing mention into a progress bar.
///
/// One type for both directions. A parent and a child are the same six
/// facts seen from either end, and the pane draws them the same way.
public struct RelatedIssue: Identifiable, Hashable, Sendable {
    public var id: String { "\(repository)#\(number)" }
    public let number: Int
    public let title: String
    /// "owner/name". Sub-issues can live in another repository, and the
    /// row says so when they do.
    public let repository: String
    public let url: URL
    public let state: LinkedSummary.State
    /// Nil where the organisation has no types, or none was set.
    public let type: IssueType?

    public init(
        number: Int,
        title: String,
        repository: String,
        url: URL,
        state: LinkedSummary.State,
        type: IssueType? = nil
    ) {
        self.number = number
        self.title = title
        self.repository = repository
        self.url = url
        self.state = state
        self.type = type
    }

    /// Counted as done, which is what closing it means here.
    public var isClosed: Bool { state != .open }

    /// The same issue as something the preview panel can look up.
    ///
    /// `.closes` is the strong kind, which is what this is: GitHub records
    /// the relation itself rather than it being a number somebody wrote in
    /// a sentence. The name is about where the link came from, not about
    /// a sub-issue closing its parent.
    public var link: ItemLink {
        ItemLink(
            reference: ItemReference(repository: repository, number: number),
            kind: .closes,
            title: title,
            url: url,
            state: state
        )
    }
}

/// How far through its children an issue is.
///
/// Taken from GitHub's own summary rather than counted off the rows,
/// because the rows stop at a limit and the summary does not: an issue
/// with sixty children would otherwise report progress through the first
/// fifty of them.
///
/// That also means `completed` is GitHub's definition -- every closed
/// child, including one closed as not planned. Counting it our own way
/// would give a number that disagrees with the one on the website for the
/// same issue, which is worse than the quibble it fixes. The rows show
/// which ones were dropped.
public struct SubIssueProgress: Hashable, Sendable {
    public let total: Int
    public let completed: Int

    public init(total: Int, completed: Int) {
        self.total = max(0, total)
        // Never more done than there are, however the two were counted.
        self.completed = min(max(0, completed), max(0, total))
    }

    public var remaining: Int { total - completed }
    public var isFinished: Bool { total > 0 && completed == total }

    /// Nil where there is nothing to be through, so a bar is not drawn for
    /// an issue with no children.
    public var fraction: Double? {
        guard total > 0 else { return nil }
        return Double(completed) / Double(total)
    }

    /// "6 of 11 done" -- the count first, because that is the question.
    ///
    /// A percentage would be the smaller fact: three of four and seventy
    /// of ninety are both three quarters, and only one of them is a
    /// morning's work.
    public var summary: String { "\(completed) of \(total) done" }
}
