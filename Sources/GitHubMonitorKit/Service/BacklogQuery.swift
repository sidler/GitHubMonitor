import Foundation

/// What was open at the end of each period, and how much of it was draft.
///
/// A count of what *stands* rather than of what happened, which is a
/// different question from the rest of the trend charts and needs a
/// different fetch. GitHub can say how many pull requests are open now; it
/// cannot say how many were open in March. So the pull requests that were
/// open at any period boundary are read once each, with the timestamps that
/// say when they came and went, and the twelve counts are worked out here.
public enum BacklogQuery {
    public static let pageSize = 100

    /// Pull requests created in the period that outlived it.
    ///
    /// The ones created and closed inside the same period are left out on
    /// purpose: they were never open at any boundary, so they belong to no
    /// bar on the chart, and in a busy repository they are most of what was
    /// created. For one month of a repository doing five hundred pull
    /// requests, this asks about a hundred and twenty.
    ///
    /// `-closed:` rather than two searches for "still open" and "closed
    /// later": one request instead of two, and the qualifier errs towards
    /// including a pull request rather than dropping one -- which is the
    /// right way round, since every answer is checked against its own dates
    /// before it is counted.
    public static func query(repository: String, period: DateInterval) -> String {
        let range = TrendQuery.range(period)
        return "repo:\(repository) is:pr created:\(range) -closed:\(range)"
    }

    /// Everything that was already open when the first period began.
    ///
    /// Without this the early bars would count only what the window itself
    /// created, and a repository's standing backlog -- the pull requests
    /// that have been sitting there since before the chart starts -- would
    /// appear to grow out of nothing.
    public static func openingQuery(repository: String, before: Date) -> String {
        let day = TrendQuery.day.string(from: before)
        return "repo:\(repository) is:pr created:<\(day) -closed:<\(day)"
    }

    /// GitHub's search hands back a thousand results and says nothing when
    /// it has more -- not an error, just a last page that claims to be one.
    /// A count drawn from it has to notice.
    public static let searchCap = 1000

    /// Twenty is far past what any pull request collects: going back and
    /// forth between draft and ready more than a handful of times is not
    /// something that happens.
    static let draftEvents = 20

    public static let document = """
    query($query: String!, $cursor: String) {
      rateLimit { remaining cost }
      search(query: $query, type: ISSUE, first: \(pageSize), after: $cursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            id
            createdAt
            closedAt
            isDraft
            author { __typename }
            timelineItems(
              itemTypes: [READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT],
              first: \(draftEvents)
            ) {
              nodes {
                __typename
                ... on ReadyForReviewEvent { createdAt }
                ... on ConvertToDraftEvent { createdAt }
              }
            }
          }
        }
      }
    }
    """

    public static func page(
        from payload: [String: Any]
    ) -> TrendQuery.Page<BacklogPullRequest> {
        let search = payload["search"] as? [String: Any]
        let nodes = search?["nodes"] as? [[String: Any]] ?? []
        return TrendQuery.Page(
            items: nodes.compactMap(pullRequest(from:)),
            cursor: TrendQuery.cursor(from: search),
            remainingQuota: TrendQuery.remainingQuota(from: payload)
        )
    }

    /// How many the search matched, so a window wider than GitHub will
    /// answer can be said out loud instead of drawn short.
    public static func total(from payload: [String: Any]) -> Int? {
        (payload["search"] as? [String: Any])?["issueCount"] as? Int
    }

    static func pullRequest(from node: [String: Any]) -> BacklogPullRequest? {
        guard
            let key = node["id"] as? String,
            let createdAt = GitHubDate.optional(from: node["createdAt"] as? String)
        else { return nil }

        let timeline = (node["timelineItems"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let changes = timeline.compactMap { event -> DraftChange? in
            guard
                let kind = event["__typename"] as? String,
                let at = GitHubDate.optional(from: event["createdAt"] as? String)
            else { return nil }
            return DraftChange(at: at, toDraft: kind == "ConvertToDraftEvent")
        }

        return BacklogPullRequest(
            key: key,
            isBot: TrendQuery.isBot(node["author"] as? [String: Any]),
            createdAt: createdAt,
            closedAt: GitHubDate.optional(from: node["closedAt"] as? String),
            isDraft: node["isDraft"] as? Bool ?? false,
            draftChanges: changes
        )
    }
}
