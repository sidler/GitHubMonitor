import Foundation

/// A pull request that is waiting for the user's review.
public struct PullRequestItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let number: Int
    public let title: String
    /// "owner/name"
    public let repository: String
    public let author: String
    /// Author's avatar; nil when GitHub reports none (e.g. a deleted user).
    public let authorAvatarURL: URL?
    public let url: URL
    public let isDraft: Bool
    public let updatedAt: Date
    public let reviewDecision: ReviewDecision
    public let checks: ChecksStatus

    public init(
        id: String,
        number: Int,
        title: String,
        repository: String,
        author: String,
        authorAvatarURL: URL?,
        url: URL,
        isDraft: Bool,
        updatedAt: Date,
        reviewDecision: ReviewDecision,
        checks: ChecksStatus
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.repository = repository
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.url = url
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.reviewDecision = reviewDecision
        self.checks = checks
    }
}

public enum ReviewDecision: String, Sendable, Hashable {
    case approved
    case changesRequested
    case reviewRequired
    case none

    public var label: String {
        switch self {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .reviewRequired: "Review required"
        case .none: "No review"
        }
    }

    public var symbolName: String {
        switch self {
        case .approved: "checkmark.seal.fill"
        case .changesRequested: "arrow.uturn.backward.circle.fill"
        case .reviewRequired: "eye.circle"
        case .none: "circle.dashed"
        }
    }
}

public enum ChecksStatus: String, Sendable, Hashable {
    case success
    case failure
    case pending
    case none

    public var label: String {
        switch self {
        case .success: "Checks passing"
        case .failure: "Checks failing"
        case .pending: "Checks running"
        case .none: "No checks"
        }
    }

    public var symbolName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .pending: "clock.fill"
        case .none: "minus.circle"
        }
    }
}

/// Why GitHub sent a notification. Mirrors the `reason` field of the REST
/// notifications API; only the values we offer as filters are modelled
/// explicitly, everything else falls into `other`.
public enum NotificationReason: String, Sendable, Hashable, CaseIterable, Codable {
    case mention
    case teamMention = "team_mention"
    case reviewRequested = "review_requested"
    case assign
    case comment
    case author
    case subscribed
    case stateChange = "state_change"
    case other

    public init(apiValue: String) {
        self = NotificationReason(rawValue: apiValue) ?? .other
    }

    public var label: String {
        switch self {
        case .mention: "Mentioned me directly"
        case .teamMention: "Mentioned one of my teams"
        case .reviewRequested: "Review requested"
        case .assign: "Assigned to me"
        case .comment: "Comment on a thread I'm in"
        case .author: "Activity on something I authored"
        case .subscribed: "Repository I watch"
        case .stateChange: "Thread was opened or closed"
        case .other: "Other"
        }
    }

    /// Reasons offered as checkboxes in settings, in display order.
    public static let selectable: [NotificationReason] = [
        .mention, .teamMention, .reviewRequested, .assign, .comment, .author,
    ]
}

/// An unread GitHub notification thread.
public struct NotificationItem: Identifiable, Hashable, Sendable {
    /// GitHub's notification thread id -- also the handle used to mark it read.
    public let id: String
    public let title: String
    public let repository: String
    /// Avatar of the repository owner -- the notification API carries no
    /// commenter identity, so this is the closest available signal.
    public let avatarURL: URL?
    public let reason: NotificationReason
    public let updatedAt: Date
    /// "Issue", "PullRequest", "Commit", ...
    public let subjectType: String
    /// API URL of the newest comment; the body is fetched lazily from here.
    public let latestCommentAPIURL: URL?
    /// API URL of the subject, used to resolve a browser URL on demand.
    public let subjectAPIURL: URL?

    /// Icon for the kind of thing this notification is about.
    ///
    /// More useful than an avatar here: the notifications API carries no
    /// commenter identity, so the only avatar available is the repository
    /// owner's -- identical for every row within one organisation.
    public var symbolName: String {
        switch subjectType {
        case "PullRequest": "arrow.triangle.pull"
        case "Issue": "smallcircle.filled.circle"
        case "Commit": "arrow.triangle.branch"
        case "Release": "tag"
        case "Discussion": "bubble.left.and.bubble.right"
        case "CheckSuite": "checkmark.seal"
        default: "bell"
        }
    }

    /// Plural heading used when the list is grouped by type.
    public var subjectTypeLabel: String {
        switch subjectType {
        case "PullRequest": "Pull requests"
        case "Issue": "Issues"
        case "Commit": "Commits"
        case "Release": "Releases"
        case "Discussion": "Discussions"
        case "CheckSuite": "Check suites"
        default: subjectType
        }
    }

    public init(
        id: String,
        title: String,
        repository: String,
        avatarURL: URL?,
        reason: NotificationReason,
        updatedAt: Date,
        subjectType: String,
        latestCommentAPIURL: URL?,
        subjectAPIURL: URL?
    ) {
        self.id = id
        self.title = title
        self.repository = repository
        self.avatarURL = avatarURL
        self.reason = reason
        self.updatedAt = updatedAt
        self.subjectType = subjectType
        self.latestCommentAPIURL = latestCommentAPIURL
        self.subjectAPIURL = subjectAPIURL
    }
}
