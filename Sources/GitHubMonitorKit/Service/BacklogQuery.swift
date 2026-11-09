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
        // A day on either side, because the two sides of this are not
        // measured the same way. `TrendQuery.range` writes bare days in the
        // reader's own time zone and GitHub reads a bare day as UTC, while
        // the counting below asks about `period.end` to the second. East of
        // UTC the two windows disagree by the offset at the start, west of
        // it at the end, and the pull requests in that gap were simply
        // absent from the period's bar.
        //
        // Asking for too much is safe and asking for too little is not:
        // every answer is checked against its own timestamps before it is
        // counted, and the set is keyed by id, so an extra day of overlap
        // between periods costs nothing but the rows.
        let wanted = TrendQuery.range(padded(period, byDays: 1) ?? period)

        // The pull requests created and closed inside the same period were
        // never open at a boundary, and in a busy repository they are most
        // of what was created -- but the exclusion has to err the other
        // way, so it is narrowed by a day rather than widened. A period too
        // short to narrow simply does not use it.
        guard let inner = padded(period, byDays: -1) else {
            return "repo:\(repository) is:pr created:\(wanted)"
        }
        return "repo:\(repository) is:pr created:\(wanted) -closed:\(TrendQuery.range(inner))"
    }

    /// The period with each end moved out (or in, for a negative count) by
    /// whole days. Nil where moving the ends in would leave nothing.
    static func padded(_ period: DateInterval, byDays days: Int) -> DateInterval? {
        let day: TimeInterval = 86_400
        let start = period.start.addingTimeInterval(-Double(days) * day)
        let end = period.end.addingTimeInterval(Double(days) * day)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Everything that was already open when the first period began.
    ///
    /// Without this the early bars would count only what the window itself
    /// created, and a repository's standing backlog -- the pull requests
    /// that have been sitting there since before the chart starts -- would
    /// appear to grow out of nothing.
    public static func openingQuery(repository: String, before: Date) -> String {
        // A day later than the window starts, for the same reason the
        // per-period range is padded: too many is harmless, too few is a
        // bar that is quietly short.
        let day = TrendQuery.day.string(from: before.addingTimeInterval(86_400))
        let inner = TrendQuery.day.string(from: before.addingTimeInterval(-86_400))
        return "repo:\(repository) is:pr created:<\(day) -closed:<\(inner)"
    }

    /// GitHub's search hands back a thousand results and says nothing when
    /// it has more -- not an error, just a last page that claims to be one.
    /// A count drawn from it has to notice.
    public static let searchCap = 1000

    /// How many moves of either kind are read back.
    ///
    /// Far past what any pull request collects: going back and forth
    /// between draft and ready, or between open and closed, more than a
    /// handful of times is not something that happens. Where one does, it
    /// is the *recent* end that has to be right -- the newest bars are the
    /// ones anybody reads -- which is why these are asked for with `last:`
    /// rather than `first:`. Asked the other way round, a pull request with
    /// more moves than this had its state decided by an event from months
    /// ago while the truth sat unread in `isDraft`.
    static let events = 30

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
            # Closing included: `closedAt` is set back to null when a pull
            # request is reopened, so it is the only record that the
            # closed stretch ever happened. A merge files a ClosedEvent
            # beside its MergedEvent, so this one type covers both.
            timelineItems(
              itemTypes: [
                READY_FOR_REVIEW_EVENT,
                CONVERT_TO_DRAFT_EVENT,
                CLOSED_EVENT,
                REOPENED_EVENT,
              ],
              last: \(events)
            ) {
              nodes {
                __typename
                ... on ReadyForReviewEvent { createdAt }
                ... on ConvertToDraftEvent { createdAt }
                ... on ClosedEvent { createdAt }
                ... on ReopenedEvent { createdAt }
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
        let moves = timeline.compactMap { event -> (kind: String, at: Date)? in
            guard
                let kind = event["__typename"] as? String,
                let at = GitHubDate.optional(from: event["createdAt"] as? String)
            else { return nil }
            return (kind, at)
        }

        let changes = moves
            .filter { $0.kind == "ConvertToDraftEvent" || $0.kind == "ReadyForReviewEvent" }
            .map { DraftChange(at: $0.at, toDraft: $0.kind == "ConvertToDraftEvent") }
        let closings = moves
            .filter { $0.kind == "ClosedEvent" || $0.kind == "ReopenedEvent" }
            .map { CloseChange(at: $0.at, toClosed: $0.kind == "ClosedEvent") }

        return BacklogPullRequest(
            key: key,
            isBot: TrendQuery.isBot(node["author"] as? [String: Any]),
            createdAt: createdAt,
            closedAt: GitHubDate.optional(from: node["closedAt"] as? String),
            isDraft: node["isDraft"] as? Bool ?? false,
            draftChanges: changes,
            closeChanges: closings
        )
    }
}
