import Foundation

/// One author's open pull requests in the dashboard repository.
public struct AuthorLoad: Identifiable, Hashable, Sendable {
    public var id: String { author }
    public let author: String
    public let avatarURL: URL?
    /// Pull requests ready for review.
    public let ready: Int
    /// Drafts, counted separately: they are not waiting on anyone yet, so
    /// folding them into the same number would overstate the queue.
    public let drafts: Int

    public var total: Int { ready + drafts }

    public init(author: String, avatarURL: URL?, ready: Int, drafts: Int) {
        self.author = author
        self.avatarURL = avatarURL
        self.ready = ready
        self.drafts = drafts
    }
}

/// One reviewer's outstanding work in the dashboard repository.
public struct ReviewerLoad: Identifiable, Hashable, Sendable {
    public var id: String { (isTeam ? "team:" : "user:") + reviewer }
    public let reviewer: String
    public let avatarURL: URL?
    public let isTeam: Bool
    /// Reviews still owed on pull requests that are ready.
    public let pending: Int
    /// Reviews owed on drafts, kept apart: nobody is blocked by those yet.
    public let onDrafts: Int
    /// Reviews already given, for context on how much has been dealt with.
    public let done: Int

    public var outstanding: Int { pending + onDrafts }

    public init(
        reviewer: String,
        avatarURL: URL?,
        isTeam: Bool,
        pending: Int,
        onDrafts: Int,
        done: Int
    ) {
        self.reviewer = reviewer
        self.avatarURL = avatarURL
        self.isTeam = isTeam
        self.pending = pending
        self.onDrafts = onDrafts
        self.done = done
    }
}

/// What the dashboard charts.
public enum DashboardGrouping: String, CaseIterable, Codable, Sendable {
    case author
    case reviewer

    public var label: String {
        switch self {
        case .author: "By author"
        case .reviewer: "By reviewer"
        }
    }
}

/// Open pull requests in one repository, summarised per author and per
/// reviewer.
public struct DashboardData: Equatable, Sendable {
    public let repository: String
    public let authors: [AuthorLoad]
    public let reviewers: [ReviewerLoad]

    public init(repository: String, authors: [AuthorLoad], reviewers: [ReviewerLoad] = []) {
        self.repository = repository
        self.authors = authors
        self.reviewers = reviewers
    }

    public var totalOutstandingReviews: Int { reviewers.reduce(0) { $0 + $1.outstanding } }

    public var totalReady: Int { authors.reduce(0) { $0 + $1.ready } }
    public var totalDrafts: Int { authors.reduce(0) { $0 + $1.drafts } }
    public var total: Int { totalReady + totalDrafts }

    /// Builds the summary from a repository's open pull requests.
    ///
    /// Sorted by the number ready for review rather than the raw total: the
    /// chart is about who is waiting on a review, and someone with six drafts
    /// is not blocking anybody.
    public static func summarise(_ items: [PullRequestItem], repository: String) -> DashboardData {
        var ready: [String: Int] = [:]
        var drafts: [String: Int] = [:]
        var avatars: [String: URL?] = [:]

        for item in items {
            avatars[item.author] = item.authorAvatarURL
            if item.isDraft {
                drafts[item.author, default: 0] += 1
            } else {
                ready[item.author, default: 0] += 1
            }
        }

        let authors = Set(ready.keys).union(drafts.keys)
            .map { author in
                AuthorLoad(
                    author: author,
                    avatarURL: avatars[author] ?? nil,
                    ready: ready[author] ?? 0,
                    drafts: drafts[author] ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.ready != rhs.ready { return lhs.ready > rhs.ready }
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.author.localizedStandardCompare(rhs.author) == .orderedAscending
            }

        return DashboardData(repository: repository, authors: authors)
    }

    /// Builds both summaries from pull requests paired with their reviewers.
    ///
    /// A reviewer's outstanding count is the pull requests where they were
    /// asked and have not answered — that is what "still owes a review"
    /// means. Reviews already left are counted separately rather than
    /// dropped, so a quiet bar can be told from an absent one.
    public static func summarise(
        _ entries: [(item: PullRequestItem, reviewers: [ReviewerStatus])],
        repository: String
    ) -> DashboardData {
        let authored = summarise(entries.map(\.item), repository: repository)

        var pending: [String: Int] = [:]
        var onDrafts: [String: Int] = [:]
        var done: [String: Int] = [:]
        var details: [String: ReviewerStatus] = [:]

        for entry in entries {
            for reviewer in entry.reviewers {
                details[reviewer.id] = reviewer
                switch reviewer.state {
                case .pending:
                    if entry.item.isDraft {
                        onDrafts[reviewer.id, default: 0] += 1
                    } else {
                        pending[reviewer.id, default: 0] += 1
                    }
                case .approved, .changesRequested, .commented, .dismissed:
                    done[reviewer.id, default: 0] += 1
                }
            }
        }

        let reviewers = details.values
            .map { status in
                ReviewerLoad(
                    reviewer: status.name,
                    avatarURL: status.avatarURL,
                    isTeam: status.isTeam,
                    pending: pending[status.id] ?? 0,
                    onDrafts: onDrafts[status.id] ?? 0,
                    done: done[status.id] ?? 0
                )
            }
            // Someone who has answered everything asked of them has nothing
            // outstanding and would only add an empty row.
            .filter { $0.outstanding > 0 }
            .sorted { lhs, rhs in
                if lhs.pending != rhs.pending { return lhs.pending > rhs.pending }
                if lhs.outstanding != rhs.outstanding { return lhs.outstanding > rhs.outstanding }
                return lhs.reviewer.localizedStandardCompare(rhs.reviewer) == .orderedAscending
            }

        return DashboardData(
            repository: repository,
            authors: authored.authors,
            reviewers: reviewers
        )
    }
}

/// Lifecycle of the dashboard's own fetch.
public enum DashboardState: Equatable, Sendable {
    /// No repository chosen yet.
    case unconfigured
    case loading
    case loaded(DashboardData)
    case failed(String)
}
