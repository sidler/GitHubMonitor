import Foundation

/// How far back the reviewer figures reach.
public enum ReviewerStatsPeriod: String, CaseIterable, Codable, Sendable {
    case month
    case quarter
    case year

    public var label: String {
        switch self {
        case .month: "30 days"
        case .quarter: "90 days"
        case .year: "12 months"
        }
    }

    public var days: Int {
        switch self {
        case .month: 30
        case .quarter: 90
        case .year: 365
        }
    }

    public func since(_ now: Date = .now) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }
}

/// Who reviewed what in a repository, and how long each answer took.
///
/// One search rather than one per reviewer: the figures are a ranking, so
/// every reviewer has to be measured over the same pull requests or the
/// rows cannot be compared with one another.
public enum ReviewerStatsQuery {
    /// A hundred, measured rather than guessed.
    ///
    /// Each node carries two connections of its own, so the worry was
    /// cost. A page of a hundred charges two points against a budget of
    /// five thousand an hour and halves the round trips, which is what
    /// the time actually goes on: a month of a busy repository came down
    /// from thirteen requests to seven.
    public static let pageSize = 100

    /// Pull requests touched in one stretch, whoever opened them.
    ///
    /// `updated:` rather than `created:`: a pull request opened in March
    /// and reviewed yesterday is yesterday's reviewing, and a window on
    /// when things were *created* would miss it.
    public static func query(repository: String, range: DateInterval) -> String {
        "repo:\(repository) is:pr updated:\(TrendQuery.range(range))"
    }

    /// GitHub's search hands back a thousand results and no more.
    ///
    /// Not as an error, either: the twentieth page simply says there is
    /// no next one. A busy repository therefore answers a ninety-day
    /// question with its most recent thousand pull requests and nothing
    /// to say it did -- which is the one failure mode a ranking must not
    /// have, because a reviewer who was busy early in the window would
    /// simply be missing.
    public static let searchCap = 1000

    /// The window, cut into months.
    ///
    /// A month at a time keeps each search well under the cap for any
    /// repository anybody reviews by hand, and the pieces are disjoint by
    /// the day -- GitHub's ranges are inclusive at both ends, so each
    /// piece stops the day before the next begins and no pull request is
    /// counted twice.
    public static func slices(since: Date, now: Date = .now) -> [DateInterval] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current

        var result: [DateInterval] = []
        var start = calendar.startOfDay(for: since)
        while start < now {
            let next = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            result.append(DateInterval(start: start, end: min(next, now)))
            start = next
        }
        // A window shorter than a month still has to be asked about.
        if result.isEmpty { result = [DateInterval(start: start, end: now)] }
        return result
    }

    public static let document = """
    query($query: String!, $cursor: String) {
      rateLimit { remaining cost }
      search(query: $query, type: ISSUE, first: \(pageSize), after: $cursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            id
            closedAt
            author { login }
            # Thirty rounds of asking is past anything a pull request here
            # collects; past it the earliest rounds are the ones lost,
            # which is the half that matters least.
            timelineItems(last: 30, itemTypes: [REVIEW_REQUESTED_EVENT]) {
              nodes {
                ... on ReviewRequestedEvent {
                  createdAt
                  requestedReviewer { ... on User { login } }
                }
              }
            }
            # Who is still being asked, which is a different thing from
            # who was ever asked.
            reviewRequests(first: 30) {
              nodes { requestedReviewer { ... on User { login } } }
            }
            # Including reviews a later push dismissed: the question is
            # when the answer came, not whether it still stands.
            reviews(first: 30) {
              nodes {
                submittedAt
                author { login __typename }
              }
            }
          }
        }
      }
    }
    """

    /// One page of pull requests, read into what the figures need.
    public static func page(
        from payload: [String: Any]
    ) -> TrendQuery.Page<ReviewedPullRequest> {
        let search = payload["search"] as? [String: Any]
        let nodes = search?["nodes"] as? [[String: Any]] ?? []
        return TrendQuery.Page(
            items: nodes.compactMap(pullRequest(from:)),
            cursor: TrendQuery.cursor(from: search),
            remainingQuota: TrendQuery.remainingQuota(from: payload)
        )
    }

    /// How many pull requests the search matched, which is what lets the
    /// view say what the figures were worked out of.
    public static func total(from payload: [String: Any]) -> Int? {
        (payload["search"] as? [String: Any])?["issueCount"] as? Int
    }

    static func pullRequest(from node: [String: Any]) -> ReviewedPullRequest? {
        guard let key = node["id"] as? String else { return nil }

        let timeline = node["timelineItems"] as? [String: Any]
        let requests = (timeline?["nodes"] as? [[String: Any]] ?? [])
            .compactMap { event -> RequestedReview? in
                // A team asked to review is not a person waiting to be
                // measured, and GitHub reports it with no login at all.
                guard
                    let reviewer = (event["requestedReviewer"] as? [String: Any])?["login"]
                        as? String,
                    let at = GitHubDate.optional(from: event["createdAt"] as? String)
                else { return nil }
                return RequestedReview(reviewer: reviewer, at: at)
            }

        let reviews = (node["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let submitted = reviews.compactMap { review -> SubmittedReview? in
            let author = review["author"] as? [String: Any]
            // Bots review on a schedule rather than when asked, so their
            // times say nothing about how long anybody waited.
            guard
                !TrendQuery.isBot(author),
                let login = author?["login"] as? String,
                let at = GitHubDate.optional(from: review["submittedAt"] as? String)
            else { return nil }
            return SubmittedReview(reviewer: login, at: at)
        }

        let outstanding = (node["reviewRequests"] as? [String: Any])?["nodes"]
            as? [[String: Any]] ?? []
        let stillRequested = Set(
            outstanding.compactMap {
                ($0["requestedReviewer"] as? [String: Any])?["login"] as? String
            }
        )

        guard !requests.isEmpty || !submitted.isEmpty else { return nil }

        return ReviewedPullRequest(
            key: key,
            closedAt: GitHubDate.optional(from: node["closedAt"] as? String),
            author: (node["author"] as? [String: Any])?["login"] as? String,
            requests: requests,
            reviews: submitted,
            stillRequested: stillRequested
        )
    }
}

/// The reviewer figures for one repository, as far as they were read.
public struct ReviewerStatsData: Sendable {
    public let repository: String
    public let period: ReviewerStatsPeriod
    public let since: Date
    public let stats: [ReviewerStats]
    /// How many pull requests the figures were worked out of.
    public let pullRequests: Int
    /// How much of the window has been read, so a table that is still
    /// filling says so rather than looking finished and wrong.
    public let months: (done: Int, of: Int)

    public var isComplete: Bool { months.done >= months.of }
    public var fetchedAt: Date
    /// Set when the fetch stopped early, so the view can say it is
    /// incomplete rather than quietly showing less.
    public var truncationReason: String?

    public init(
        repository: String,
        period: ReviewerStatsPeriod,
        since: Date,
        stats: [ReviewerStats],
        pullRequests: Int,
        months: (done: Int, of: Int) = (1, 1),
        fetchedAt: Date = .now,
        truncationReason: String? = nil
    ) {
        self.repository = repository
        self.period = period
        self.since = since
        self.stats = stats
        self.pullRequests = pullRequests
        self.months = months
        self.fetchedAt = fetchedAt
        self.truncationReason = truncationReason
    }
}

/// What the reviewer views have to draw, or why they have not.
public enum ReviewerStatsState: Sendable {
    case unconfigured
    case loading
    case loaded(ReviewerStatsData)
    case failed(String)

    public var data: ReviewerStatsData? {
        if case .loaded(let data) = self { return data }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        // A table still filling is still loading, whatever it can already
        // draw.
        if case .loaded(let data) = self { return !data.isComplete }
        return false
    }
}
