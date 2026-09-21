import Foundation

/// The queries behind the trend charts, and the reading of their answers.
///
/// One request per period rather than one for the whole history: GitHub's
/// search caps a result set at a thousand, the periods are what the charts
/// are made of anyway, and a period that has arrived can be drawn while the
/// next is still on the way.
public enum TrendQuery {
    public static let pageSize = 100

    /// A day, as GitHub's search qualifiers want it.
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Search ranges are inclusive on both ends, while a period's end is the
    /// first instant of the next one -- hence the second taken off.
    static func range(_ period: DateInterval) -> String {
        let last = period.end.addingTimeInterval(-1)
        return "\(day.string(from: period.start))..\(day.string(from: last))"
    }

    public static func mergedQuery(repository: String, period: DateInterval) -> String {
        "repo:\(repository) is:pr is:merged merged:\(range(period))"
    }

    /// Everything opened in the period, whatever became of it: the question
    /// is how much work arrived, not how much of it landed.
    public static func openedQuery(repository: String, period: DateInterval) -> String {
        "repo:\(repository) is:pr created:\(range(period))"
    }

    /// The merged pull requests of one period, with what the clock needs.
    ///
    /// `rateLimit` travels with every page so the fetch can stop before it
    /// exhausts the hour's budget rather than after.
    public static let mergedDocument = """
    query($query: String!, $cursor: String) {
      rateLimit { remaining cost }
      search(query: $query, type: ISSUE, first: \(pageSize), after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            createdAt
            mergedAt
            author { login __typename }
            # Twenty is past what any pull request here collects, and the
            # search slows down noticeably with more: this connection is
            # multiplied by the hundred pull requests on every page.
            reviews(first: 20) {
              nodes {
                state
                submittedAt
                author { login __typename }
              }
            }
            timelineItems(itemTypes: [READY_FOR_REVIEW_EVENT], first: 1) {
              nodes {
                ... on ReadyForReviewEvent { createdAt }
              }
            }
          }
        }
      }
    }
    """

    /// Only who opened them: the volume chart counts pull requests, and
    /// asking for nothing else keeps a period with hundreds of them cheap.
    public static let openedDocument = """
    query($query: String!, $cursor: String) {
      rateLimit { remaining cost }
      search(query: $query, type: ISSUE, first: \(pageSize), after: $cursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            author { __typename }
          }
        }
      }
    }
    """

    // MARK: - Reading

    public struct Page<Item>: Sendable where Item: Sendable {
        public let items: [Item]
        public let cursor: String?
        /// What GitHub says is left of the hourly GraphQL budget.
        public let remainingQuota: Int?
    }

    public static func mergedPage(from payload: [String: Any]) -> Page<PullRequestTiming> {
        let search = payload["search"] as? [String: Any]
        let nodes = search?["nodes"] as? [[String: Any]] ?? []
        return Page(
            items: nodes.compactMap(timing(from:)),
            cursor: cursor(from: search),
            remainingQuota: remainingQuota(from: payload)
        )
    }

    /// Opened pull requests, split into those a person opened and all of
    /// them -- the two audiences the charts switch between.
    public static func openedPage(from payload: [String: Any]) -> Page<Bool> {
        let search = payload["search"] as? [String: Any]
        let nodes = search?["nodes"] as? [[String: Any]] ?? []
        return Page(
            // One entry per pull request, true where a bot opened it.
            items: nodes.map { isBot($0["author"] as? [String: Any]) },
            cursor: cursor(from: search),
            remainingQuota: remainingQuota(from: payload)
        )
    }

    static func cursor(from search: [String: Any]?) -> String? {
        guard
            let info = search?["pageInfo"] as? [String: Any],
            info["hasNextPage"] as? Bool == true
        else { return nil }
        return info["endCursor"] as? String
    }

    static func remainingQuota(from payload: [String: Any]) -> Int? {
        (payload["rateLimit"] as? [String: Any])?["remaining"] as? Int
    }

    /// GitHub marks apps as bot accounts itself, which is steadier than
    /// guessing from names: renovate appears as a `Bot`, not as a user whose
    /// login happens to end in something.
    static func isBot(_ author: [String: Any]?) -> Bool {
        author?["__typename"] as? String == "Bot"
    }

    static func timing(from node: [String: Any]) -> PullRequestTiming? {
        guard
            let createdAt = date(node["createdAt"]),
            let mergedAt = date(node["mergedAt"])
        else { return nil }

        let author = node["author"] as? [String: Any]
        let readyAt = readyForReview(from: node) ?? createdAt

        let reviews = (node["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let byOthers = reviews.filter { review in
            let reviewer = review["author"] as? [String: Any]
            // A bot's review is a pipeline reporting in, not a colleague
            // looking; counting it would measure the CI's latency instead.
            guard !isBot(reviewer) else { return false }
            // Authors do review their own pull requests, usually to leave a
            // note. That is not someone else having looked.
            let login = reviewer?["login"] as? String
            return login != nil && login != author?["login"] as? String
        }

        // Reviews left before the pull request was ready belong to the
        // draft, and would otherwise report as a review that arrived before
        // anyone was asked.
        let submitted = byOthers.compactMap { review -> (state: String, at: Date)? in
            guard
                let at = date(review["submittedAt"]),
                at >= readyAt,
                let state = review["state"] as? String
            else { return nil }
            return (state, at)
        }

        return PullRequestTiming(
            isBot: isBot(author),
            readyAt: readyAt,
            mergedAt: mergedAt,
            firstReviewAt: submitted.map(\.at).min(),
            lastApprovalAt: submitted
                .filter { $0.state == "APPROVED" && $0.at <= mergedAt }
                .map(\.at)
                .max()
        )
    }

    static func readyForReview(from node: [String: Any]) -> Date? {
        guard
            let timeline = node["timelineItems"] as? [String: Any],
            let nodes = timeline["nodes"] as? [[String: Any]]
        else { return nil }
        return nodes.compactMap { date($0["createdAt"]) }.first
    }

    static func date(_ value: Any?) -> Date? {
        GitHubDate.optional(from: value as? String)
    }
}
