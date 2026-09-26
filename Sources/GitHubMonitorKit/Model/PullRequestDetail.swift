import Foundation

/// A single check on the pull request's head commit.
public struct CheckRun: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let status: ChecksStatus

    public init(name: String, status: ChecksStatus) {
        self.name = name
        self.status = status
    }
}

/// Where a reviewer stands.
public enum ReviewState: String, Hashable, Sendable {
    case approved
    case changesRequested
    case commented
    case dismissed
    /// Requested but not yet answered.
    case pending

    public var label: String {
        switch self {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .commented: "Commented"
        case .dismissed: "Dismissed"
        case .pending: "Awaiting review"
        }
    }

    public var symbolName: String {
        switch self {
        case .approved: "checkmark.circle.fill"
        case .changesRequested: "arrow.uturn.backward.circle.fill"
        case .commented: "bubble.left.circle.fill"
        case .dismissed: "slash.circle.fill"
        case .pending: "clock.circle"
        }
    }

    public init(apiValue: String?) {
        switch apiValue {
        case "APPROVED": self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        case "COMMENTED": self = .commented
        case "DISMISSED": self = .dismissed
        default: self = .pending
        }
    }
}

public struct ReviewerStatus: Identifiable, Hashable, Sendable {
    public var id: String { (isTeam ? "team:" : "user:") + name }
    public let name: String
    public let avatarURL: URL?
    public let state: ReviewState
    public let isTeam: Bool

    public init(name: String, avatarURL: URL?, state: ReviewState, isTeam: Bool) {
        self.name = name
        self.avatarURL = avatarURL
        self.state = state
        self.isTeam = isTeam
    }

    /// What is blocking first, what is settled last.
    ///
    /// Shared, so a list assembled here and one assembled from a fetch are
    /// in the same order -- otherwise the reviewers would visibly reshuffle
    /// the moment the fetch came back.
    public static func ordered(_ reviewers: [ReviewerStatus]) -> [ReviewerStatus] {
        reviewers.sorted { lhs, rhs in
            lhs.state == rhs.state
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : priority(lhs.state) < priority(rhs.state)
        }
    }

    static func priority(_ state: ReviewState) -> Int {
        switch state {
        case .changesRequested: 0
        case .pending: 1
        case .commented: 2
        case .approved: 3
        case .dismissed: 4
        }
    }
}

/// Everything the detail pane shows, fetched for one pull request at a time.
public struct PullRequestDetail: Hashable, Sendable {
    /// The branch being merged, and the one it targets.
    public let headBranch: String
    public let baseBranch: String
    public let additions: Int
    public let deletions: Int
    public let changedFiles: Int
    public let comments: Int
    /// The text the author wrote when opening it, as Markdown.
    ///
    /// Carried here rather than fetched on demand: it is a plain field on
    /// the pull request, so the request that already loads this pane pays
    /// nothing more for it.
    public let body: String
    /// Read again here rather than taken from the row: GitHub works it out
    /// in the background, so a pull request that was still unknown when the
    /// list loaded usually has an answer by the time its pane is opened.
    public let mergeStatus: MergeStatus
    public let checks: [CheckRun]
    public let reviewers: [ReviewerStatus]

    public init(
        headBranch: String,
        baseBranch: String,
        additions: Int,
        deletions: Int,
        changedFiles: Int,
        comments: Int,
        body: String = "",
        mergeStatus: MergeStatus = .unknown,
        checks: [CheckRun],
        reviewers: [ReviewerStatus]
    ) {
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.comments = comments
        self.body = body
        self.mergeStatus = mergeStatus
        self.checks = checks
        self.reviewers = reviewers
    }

    /// The same detail with this person shown as having approved.
    ///
    /// Written from what GitHub just confirmed rather than waited for: a
    /// detail fetched in the moment after the mutation can still answer with
    /// the review set from before it, and the pane would then show the state
    /// the approval just left behind. The fetch that follows replaces this
    /// with GitHub's own account of it.
    public func countingApproval(by login: String, avatarURL: URL?) -> PullRequestDetail {
        let others = reviewers.filter {
            $0.isTeam || $0.name.caseInsensitiveCompare(login) != .orderedSame
        }
        let approved = ReviewerStatus(
            name: login, avatarURL: avatarURL, state: .approved, isTeam: false
        )
        return PullRequestDetail(
            headBranch: headBranch,
            baseBranch: baseBranch,
            additions: additions,
            deletions: deletions,
            changedFiles: changedFiles,
            comments: comments,
            body: body,
            mergeStatus: mergeStatus,
            checks: checks,
            reviewers: ReviewerStatus.ordered(others + [approved])
        )
    }

    public var failingChecks: [CheckRun] { checks.filter { $0.status == .failure } }
    public var passingChecks: [CheckRun] { checks.filter { $0.status == .success } }
    public var runningChecks: [CheckRun] { checks.filter { $0.status == .pending } }
}

/// Lifecycle of a lazily fetched detail.
public enum DetailState: Equatable, Sendable {
    case loading
    case loaded(PullRequestDetail)
    case failed(String)
}
