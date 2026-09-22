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

    /// Every pull request opened in one period of a repository, for the
    /// ranking that covers more than your own work.
    public static func repositoryQuery(repository: String, period: DateInterval) -> String {
        "repo:\(repository) is:pr created:\(TrendQuery.range(period))"
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
            # To leave your own replies out: the question is what other
            # people said on your pull requests.
            author { login }
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

        // Your own replies are not what these charts are about: you are in
        // every one of your pull requests, so counting yourself would put
        // you at the top of the ranking and say nothing.
        let mine = (node["author"] as? [String: Any])?["login"] as? String
        func isMine(_ author: [String: Any]?) -> Bool {
            guard let mine, let login = author?["login"] as? String else { return false }
            return login == mine
        }

        var byPeople: [String: Int] = [:]
        var byEveryone: [String: Int] = [:]
        func credit(_ author: [String: Any]?, _ count: Int) {
            guard count > 0, !isMine(author), let login = author?["login"] as? String else { return }
            byEveryone[login, default: 0] += count
            if !TrendQuery.isBot(author) { byPeople[login, default: 0] += count }
        }

        let comments = node["comments"] as? [String: Any]
        let conversationNodes = comments?["nodes"] as? [[String: Any]] ?? []
        for comment in conversationNodes {
            credit(comment["author"] as? [String: Any], 1)
        }

        // A review counts as one comment for its author, plus whatever they
        // wrote inside it: leaving "looks good" and leaving nine notes on
        // the diff are not the same amount of attention.
        var reviewComments = 0
        var reviewCommentsFromPeople = 0
        for review in (node["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [] {
            let author = review["author"] as? [String: Any]
            guard !isMine(author) else { continue }
            let inline = (review["comments"] as? [String: Any])?["totalCount"] as? Int ?? 0
            credit(author, inline + 1)
            reviewComments += inline + 1
            if !TrendQuery.isBot(author) { reviewCommentsFromPeople += inline + 1 }
        }

        // The conversation's own total is exact even where the nodes were
        // capped, so it is what the count starts from; what the cap costs is
        // knowing which of those comments were yours or a bot's.
        let conversation = comments?["totalCount"] as? Int ?? 0
        let ownComments = conversationNodes.count { isMine($0["author"] as? [String: Any]) }
        let botComments = conversationNodes.count {
            TrendQuery.isBot($0["author"] as? [String: Any])
        }

        return MyPullRequestFacts(
            createdAt: createdAt,
            commentsFromPeople: conversation - ownComments - botComments + reviewCommentsFromPeople,
            commentsFromEveryone: conversation - ownComments + reviewComments,
            commentersFromPeople: byPeople,
            commentersFromEveryone: byEveryone
        )
    }
}
