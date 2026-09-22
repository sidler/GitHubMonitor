import Foundation

/// What one of your own pull requests contributes to the charts.
public struct MyPullRequestFacts: Hashable, Sendable {
    public let createdAt: Date
    /// Conversation comments plus the comments left inside reviews.
    public let commentsFromPeople: Int
    public let commentsFromEveryone: Int
    /// Login to how many of those comments they wrote.
    public let commentersFromPeople: [String: Int]
    public let commentersFromEveryone: [String: Int]

    public init(
        createdAt: Date,
        commentsFromPeople: Int,
        commentsFromEveryone: Int,
        commentersFromPeople: [String: Int],
        commentersFromEveryone: [String: Int]
    ) {
        self.createdAt = createdAt
        self.commentsFromPeople = commentsFromPeople
        self.commentsFromEveryone = commentsFromEveryone
        self.commentersFromPeople = commentersFromPeople
        self.commentersFromEveryone = commentersFromEveryone
    }
}

/// The queries behind the personal trend charts.
///
/// Your own pull requests, not a repository's: the searches are scoped by
/// author instead, and by whatever repository filters the rest of the app is
/// working under, so the charts describe the same work the lists do.
public enum MyTrendQuery {
    public static let pageSize = 100

    public static func openedQuery(
        login: String,
        repositoryFilters: [String],
        period: DateInterval
    ) -> String {
        "is:pr author:\(login) created:\(TrendQuery.range(period))"
            + PullRequestQuery.repositoryScope(repositoryFilters)
    }

    public static func mergedQuery(
        login: String,
        repositoryFilters: [String],
        period: DateInterval
    ) -> String {
        "is:pr author:\(login) is:merged merged:\(TrendQuery.range(period))"
            + PullRequestQuery.repositoryScope(repositoryFilters)
    }

    /// Conversation comments with who wrote them, and the reviews, which
    /// carry their own inline comments.
    ///
    /// Fifty and twenty are past what a pull request here collects. Where one
    /// goes beyond them the totals stay exact -- they come from the counts
    /// GitHub reports -- and only the ranking of who said what misses the
    /// tail.
    public static let document = """
    query($query: String!, $cursor: String) {
      rateLimit { remaining cost }
      search(query: $query, type: ISSUE, first: \(pageSize), after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            createdAt
            comments(first: 50) {
              totalCount
              nodes { author { login __typename } }
            }
            reviews(first: 20) {
              nodes {
                author { login __typename }
                comments { totalCount }
              }
            }
          }
        }
      }
    }
    """

    public static func page(from payload: [String: Any]) -> TrendQuery.Page<MyPullRequestFacts> {
        let search = payload["search"] as? [String: Any]
        let nodes = search?["nodes"] as? [[String: Any]] ?? []
        return TrendQuery.Page(
            items: nodes.compactMap(facts(from:)),
            cursor: TrendQuery.cursor(from: search),
            remainingQuota: TrendQuery.remainingQuota(from: payload)
        )
    }

    static func facts(from node: [String: Any]) -> MyPullRequestFacts? {
        guard let createdAt = TrendQuery.date(node["createdAt"]) else { return nil }

        var byPeople: [String: Int] = [:]
        var byEveryone: [String: Int] = [:]
        func credit(_ author: [String: Any]?, _ count: Int) {
            guard count > 0, let login = author?["login"] as? String else { return }
            byEveryone[login, default: 0] += count
            if !TrendQuery.isBot(author) { byPeople[login, default: 0] += count }
        }

        let comments = node["comments"] as? [String: Any]
        for comment in comments?["nodes"] as? [[String: Any]] ?? [] {
            credit(comment["author"] as? [String: Any], 1)
        }

        // A review counts as one comment for its author, plus whatever they
        // wrote inside it: leaving "looks good" and leaving nine notes on
        // the diff are not the same amount of attention.
        var reviewComments = 0
        var reviewCommentsFromPeople = 0
        for review in (node["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [] {
            let author = review["author"] as? [String: Any]
            let inline = (review["comments"] as? [String: Any])?["totalCount"] as? Int ?? 0
            credit(author, inline + 1)
            reviewComments += inline + 1
            if !TrendQuery.isBot(author) { reviewCommentsFromPeople += inline + 1 }
        }

        // The conversation's own total is exact even where the nodes were
        // capped, so it is the one counted; what the cap costs is knowing
        // which of those comments came from a bot.
        let conversation = comments?["totalCount"] as? Int ?? 0
        let conversationFromPeople = conversation - botConversationComments(comments)

        return MyPullRequestFacts(
            createdAt: createdAt,
            commentsFromPeople: conversationFromPeople + reviewCommentsFromPeople,
            commentsFromEveryone: conversation + reviewComments,
            commentersFromPeople: byPeople,
            commentersFromEveryone: byEveryone
        )
    }

    static func botConversationComments(_ comments: [String: Any]?) -> Int {
        (comments?["nodes"] as? [[String: Any]] ?? [])
            .count { TrendQuery.isBot($0["author"] as? [String: Any]) }
    }
}
