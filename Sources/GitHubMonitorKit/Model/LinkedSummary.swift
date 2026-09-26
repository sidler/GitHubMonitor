import Foundation

/// Enough of a linked issue or pull request to answer "what is this about"
/// without leaving what you were reading.
///
/// One type for both kinds. They differ in what is worth saying about them
/// -- labels against checks, a milestone against a branch -- but the
/// question being asked of them is the same, and so is the panel.
public struct LinkedSummary: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case issue
        case pullRequest
    }

    /// Where the item stands. Drawn from two different GraphQL enums plus
    /// the draft flag, because "open" on a pull request nobody may merge
    /// yet is not the same answer as "open".
    public enum State: Hashable, Sendable {
        case open
        case draft
        case merged
        case closed
        /// An issue closed as not planned, which is not the same as done.
        case notPlanned

        public var label: String {
            switch self {
            case .open: "Open"
            case .draft: "Draft"
            case .merged: "Merged"
            case .closed: "Closed"
            case .notPlanned: "Closed as not planned"
            }
        }

        public var symbolName: String {
            switch self {
            case .open: "circle"
            case .draft: "circle.dashed"
            case .merged: "arrow.triangle.merge"
            case .closed: "checkmark.circle.fill"
            case .notPlanned: "slash.circle"
            }
        }
    }

    public let reference: ItemReference
    public let kind: Kind
    public let state: State
    public let title: String
    public let author: String
    public let authorAvatarURL: URL?
    public let url: URL
    public let createdAt: Date
    public let updatedAt: Date
    public let body: String
    public let comments: Int
    /// Issues only; a pull request's labels are not what anyone opens this
    /// panel for.
    public let labels: [IssueLabel]
    /// Pull requests only.
    public let checks: ChecksStatus?
    public let reviewDecision: ReviewDecision?
    public let changedFiles: Int?
    public let additions: Int?
    public let deletions: Int?

    public var id: String { reference.id }

    public init(
        reference: ItemReference,
        kind: Kind,
        state: State,
        title: String,
        author: String,
        authorAvatarURL: URL? = nil,
        url: URL,
        createdAt: Date,
        updatedAt: Date,
        body: String = "",
        comments: Int = 0,
        labels: [IssueLabel] = [],
        checks: ChecksStatus? = nil,
        reviewDecision: ReviewDecision? = nil,
        changedFiles: Int? = nil,
        additions: Int? = nil,
        deletions: Int? = nil
    ) {
        self.reference = reference
        self.kind = kind
        self.state = state
        self.title = title
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.url = url
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.body = body
        self.comments = comments
        self.labels = labels
        self.checks = checks
        self.reviewDecision = reviewDecision
        self.changedFiles = changedFiles
        self.additions = additions
        self.deletions = deletions
    }
}

/// Lifecycle of one looked-up link.
///
/// `missing` is its own case rather than a failure: a number read out of a
/// sentence may simply not be an issue, and that is an answer, not an
/// error. Nothing is drawn for it.
public enum LinkedSummaryState: Equatable, Sendable {
    case loading
    case loaded(LinkedSummary)
    case missing
    case failed(String)
}
