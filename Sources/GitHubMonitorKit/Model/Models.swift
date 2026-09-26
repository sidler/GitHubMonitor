import Foundation

/// What the lists have in common: a repository they belong to, and the two
/// dates they can be ordered by.
///
/// The repository filter and the sort are written once against this rather
/// than once per list. Two copies would eventually disagree, and a sidebar
/// whose counts disagree with its lists is worse than no counts.
public protocol ListedItem: Identifiable, Sendable where ID == String {
    var repository: String { get }
    func date(for sort: PullRequestSort) -> Date
}

/// Where a pull request stands, as GitHub's own enum has it.
public enum PullRequestState: String, Hashable, Sendable {
    case open
    case closed
    case merged

    public init(apiValue: String?) {
        switch apiValue {
        case "MERGED": self = .merged
        case "CLOSED": self = .closed
        default: self = .open
        }
    }
}

/// A pull request that is waiting for the user's review.
public struct PullRequestItem: Identifiable, Hashable, Sendable, ListedItem {
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
    /// Open, closed or merged. Read rather than assumed: a list can be
    /// written with `is:merged`, and a pull request can be merged by
    /// somebody else between two refreshes.
    public let state: PullRequestState
    /// When the pull request was opened, and when it last saw activity.
    public let createdAt: Date
    public let updatedAt: Date
    public let reviewDecision: ReviewDecision
    public let checks: ChecksStatus
    /// Whether it still merges into its base branch.
    public let mergeStatus: MergeStatus
    /// What approving from inside the app needs to know: which commit the
    /// diff on screen belongs to, whether this is the viewer's own work,
    /// where their own review stands, and whether a merge is already armed
    /// and waiting for one more yes.
    public let headCommit: String?
    public let viewerDidAuthor: Bool
    public let viewerReview: ViewerReview?
    public let isAutoMergeArmed: Bool

    /// When the review was asked of the signed-in person.
    ///
    /// Nil where no request names them: a request made of a team names the
    /// team, and the author's own pull requests were never requested of
    /// them at all. Nothing is drawn for those -- a colour that meant
    /// "waiting too long on you" in one list and something else in another
    /// would mean nothing in both.
    public let reviewRequestedAt: Date?
    /// Where the reviewers stand, for the counts in the row.
    public let reviews: ReviewTally
    /// The issues this pull request answers.
    ///
    /// What a row can know without paying for it: GitHub's own links and a
    /// number at the head of the title. Whatever else the description names
    /// is found when the description is loaded, which is not here.
    public let links: [ItemLink]
    /// How many issues GitHub says this closes, of which at most five are
    /// in `links`. Said rather than shown, so a sweep does not look like
    /// five issues.
    public let linkedTotal: Int

    public init(
        id: String,
        number: Int,
        title: String,
        repository: String,
        author: String,
        authorAvatarURL: URL?,
        url: URL,
        isDraft: Bool,
        state: PullRequestState = .open,
        createdAt: Date? = nil,
        updatedAt: Date,
        reviewDecision: ReviewDecision,
        checks: ChecksStatus,
        mergeStatus: MergeStatus = .unknown,
        headCommit: String? = nil,
        viewerDidAuthor: Bool = false,
        viewerReview: ViewerReview? = nil,
        isAutoMergeArmed: Bool = false,
        reviewRequestedAt: Date? = nil,
        reviews: ReviewTally = .none,
        links: [ItemLink] = [],
        linkedTotal: Int? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.repository = repository
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.url = url
        self.isDraft = isDraft
        self.state = state
        // Older payloads and callers that only care about activity leave it
        // out; falling back keeps a row sortable either way.
        self.createdAt = createdAt ?? updatedAt
        self.updatedAt = updatedAt
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.mergeStatus = mergeStatus
        self.headCommit = headCommit
        self.viewerDidAuthor = viewerDidAuthor
        self.viewerReview = viewerReview
        self.isAutoMergeArmed = isAutoMergeArmed
        self.reviewRequestedAt = reviewRequestedAt
        self.reviews = reviews
        self.links = links
        self.linkedTotal = linkedTotal ?? links.count
    }

    /// The same pull request with this person's approval counted.
    ///
    /// The tally and their own review move; `reviewDecision` does not. That
    /// field is the pull request's verdict, and one approval does not settle
    /// it where two are required -- the next refresh brings GitHub's answer.
    public func countingViewerApproval(at moment: Date = .now) -> PullRequestItem {
        PullRequestItem(
            id: id, number: number, title: title, repository: repository, author: author,
            authorAvatarURL: authorAvatarURL, url: url, isDraft: isDraft, state: state,
            createdAt: createdAt, updatedAt: updatedAt,
            reviewDecision: reviewDecision, checks: checks, mergeStatus: mergeStatus,
            headCommit: headCommit, viewerDidAuthor: viewerDidAuthor,
            viewerReview: ViewerReview(state: .approved, submittedAt: moment),
            isAutoMergeArmed: isAutoMergeArmed,
            reviewRequestedAt: reviewRequestedAt,
            reviews: reviews.countingApproval(replacing: viewerReview?.state),
            links: links,
            linkedTotal: linkedTotal
        )
    }

    /// How long the review has been waiting, as of now.
    public func waiting(asOf now: Date = .now) -> TimeInterval? {
        reviewRequestedAt.map { now.timeIntervalSince($0) }
    }

    /// The timestamp the list is ordered on.
    public func date(for sort: PullRequestSort) -> Date {
        switch sort {
        case .updated: updatedAt
        case .created: createdAt
        }
    }
}

/// What a pull request list is ordered by. Newest first either way: a review
/// queue is read from the top, and the oldest entry is never the one being
/// looked for.
public enum PullRequestSort: String, CaseIterable, Codable, Sendable {
    /// Last activity -- a comment, a push, a review.
    case updated
    /// When the pull request was opened.
    case created

    public var label: String {
        switch self {
        case .updated: "Last updated"
        case .created: "Date opened"
        }
    }

    /// Prefix for the timestamp in a row, so the column being sorted on says
    /// which date it is showing.
    public var rowPrefix: String {
        switch self {
        case .updated: "updated"
        case .created: "opened"
        }
    }

    public var symbolName: String {
        switch self {
        case .updated: "clock.arrow.circlepath"
        case .created: "calendar"
        }
    }
}

/// How many reviewers have accepted, asked for changes, or not answered yet.
///
/// The row's review decision says what the pull request needs as a whole; the
/// tally says how far it has got, which is the difference between "one person
/// still to go" and "nobody has looked".
public struct ReviewTally: Hashable, Sendable {
    /// Reviewers whose latest opinion is an approval.
    public let accepted: Int
    /// Reviewers whose latest opinion asks for changes.
    public let declined: Int
    /// Review requests still outstanding.
    ///
    /// Someone asked again after they had already reviewed counts both here
    /// and under their earlier opinion -- GitHub keeps both, and dropping
    /// either would hide that they have been asked a second time.
    public let pending: Int

    public static let none = ReviewTally(accepted: 0, declined: 0, pending: 0)

    public var total: Int { accepted + declined + pending }
    public var isEmpty: Bool { total == 0 }

    public init(accepted: Int, declined: Int, pending: Int) {
        self.accepted = accepted
        self.declined = declined
        self.pending = pending
    }

    /// The counts worth drawing: a zero says nothing a missing symbol does
    /// not already say, and every row carries at least one of these.
    public var entries: [(kind: ReviewTallyKind, count: Int)] {
        ReviewTallyKind.allCases
            .map { ($0, count(of: $0)) }
            .filter { $0.1 > 0 }
    }

    /// One more approval, and one fewer of whatever this person's previous
    /// review was -- an approval that supersedes their own request for
    /// changes must not leave both standing.
    public func countingApproval(replacing previous: ReviewState?) -> ReviewTally {
        ReviewTally(
            accepted: accepted + (previous == .approved ? 0 : 1),
            declined: max(0, declined - (previous == .changesRequested ? 1 : 0)),
            pending: max(0, pending - 1)
        )
    }

    public func count(of kind: ReviewTallyKind) -> Int {
        switch kind {
        case .accepted: accepted
        case .declined: declined
        case .pending: pending
        }
    }
}

/// The three numbers a row reports about its reviewers.
public enum ReviewTallyKind: String, CaseIterable, Hashable, Sendable {
    case accepted
    case declined
    case pending

    /// Plural nouns: these count people, while the pull request's own
    /// review decision beside them is a state. "Objections" rather than
    /// "change requests", which would read as the same thing as the decision
    /// symbol two entries earlier in the legend.
    public var legendLabel: String {
        switch self {
        case .accepted: "approvals"
        case .declined: "objections"
        case .pending: "awaited"
        }
    }

    /// What the legend's entry means, spelled out.
    public var legendHelp: String {
        switch self {
        case .accepted: "How many reviewers have approved"
        case .declined: "How many reviewers have asked for changes"
        case .pending: "How many reviews are still outstanding"
        }
    }

    /// What the number beside the symbol means, spelled out.
    public func sentence(count: Int) -> String {
        let people = count == 1 ? "reviewer" : "reviewers"
        switch self {
        case .accepted: return "\(count) \(people) approved"
        case .declined: return "\(count) \(people) asked for changes"
        case .pending: return count == 1
            ? "1 review still outstanding"
            : "\(count) reviews still outstanding"
        }
    }

    /// People rather than seals and ticks: these count reviewers, and the
    /// symbols beside them already report the pull request's own state.
    public var symbolName: String {
        switch self {
        case .accepted: "person.crop.circle.badge.checkmark"
        case .declined: "person.crop.circle.badge.xmark"
        case .pending: "person.crop.circle.badge.clock"
        }
    }
}

public enum ReviewDecision: String, Sendable, Hashable, CaseIterable {
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

public enum ChecksStatus: String, Sendable, Hashable, CaseIterable {
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

/// The signed-in person's own last review of a pull request.
///
/// Their own, not the pull request's: a single approval does not make a pull
/// request approved where two are required, and confusing the two would have
/// the app claiming things GitHub has not said.
public struct ViewerReview: Hashable, Sendable {
    public let state: ReviewState
    public let submittedAt: Date?

    public init(state: ReviewState, submittedAt: Date?) {
        self.state = state
        self.submittedAt = submittedAt
    }
}

/// Whether a pull request still merges into the branch it targets.
///
/// `unknown` is not a failure. GitHub works the answer out in the background
/// and reports it as unknown until it has, so a pull request opened moments
/// ago arrives without one and picks it up on a later refresh. Nothing is
/// drawn for it: a symbol meaning "ask again later" tells a reviewer less
/// than an empty space does.
public enum MergeStatus: String, Sendable, Hashable, CaseIterable {
    case mergeable
    case conflicting
    case unknown

    public var label: String {
        switch self {
        case .mergeable: "Merges cleanly"
        case .conflicting: "Conflicts with its base branch"
        case .unknown: "GitHub has not worked out whether it merges"
        }
    }

    public var symbolName: String {
        switch self {
        case .mergeable: "arrow.triangle.merge"
        // A different shape rather than the same one in red: conflicts are
        // the state worth crossing the room for, and shape carries further
        // than colour in a line of small symbols.
        case .conflicting: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
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
