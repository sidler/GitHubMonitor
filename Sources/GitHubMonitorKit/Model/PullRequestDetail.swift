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
        self.mergeStatus = mergeStatus
        self.checks = checks
        self.reviewers = reviewers
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
