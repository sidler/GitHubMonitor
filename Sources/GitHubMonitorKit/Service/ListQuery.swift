import Foundation

/// One search that a list runs, ready to send.
public struct ListSearch: Hashable, Sendable {
    public let listID: String
    public let content: ListContent
    public let query: String

    public init(listID: String, content: ListContent, query: String) {
        self.listID = listID
        self.content = content
        self.query = query
    }
}

/// Turns saved lists into the searches behind them, and those into one
/// GraphQL document.
public enum ListQuery {
    /// The searches one list runs, after the global repository filter has
    /// been applied.
    ///
    /// Nothing is substituted into the query: GitHub understands `@me`
    /// itself, and resolves team membership itself as well -- a review
    /// requested from a team is returned by `review-requested:@me` for
    /// everyone on that team.
    public static func searches(
        for list: SavedList,
        repositoryFilters: [String]
    ) -> [ListSearch] {
        list.queryLines.map { query in
            ListSearch(
                listID: list.id,
                content: list.content,
                query: scoped(query, repositoryFilters: repositoryFilters)
            )
        }
    }

    /// The global repository filter, appended only where the search names no
    /// scope of its own -- a list written for one repository should not also
    /// be narrowed to whatever the settings happen to say.
    static func scoped(_ query: String, repositoryFilters: [String]) -> String {
        guard !namesAScope(query) else { return query }
        return query + PullRequestQuery.repositoryScope(repositoryFilters)
    }

    static func namesAScope(_ query: String) -> Bool {
        let scopes = ["repo:", "org:", "user:"]
        return query.split(separator: " ").contains { term in
            let lowered = term.lowercased()
            return scopes.contains { lowered.hasPrefix($0) || lowered.hasPrefix("-\($0)") }
        }
    }

    // MARK: - Document

    /// GitHub's most per page. It used to ask for fifty and stop there,
    /// which quietly cut a review queue of a hundred and nine in half --
    /// and the badge and the menu bar counted the half.
    public static let pageSize = 100

    /// How many a single search will page through before it gives up and
    /// says how many are left. A list this long is one to narrow rather
    /// than one to scroll, and every page is another request on every
    /// refresh.
    public static let maximumItems = 300

    /// Every search in one request, each under its own alias.
    ///
    /// One document rather than one per list: a refresh that fired a request
    /// per list would take as long as the slowest sum of them, and the menu
    /// bar would count lists from different moments.
    public static func document(
        _ searches: [ListSearch], cursors: [Int: String] = [:]
    ) -> String {
        let aliases = searches.enumerated().map { index, search in
            let after = cursors[index].map { ", after: \(PullRequestQuery.jsonString($0))" } ?? ""
            return """
                \(alias(index)): search(query: \(PullRequestQuery.jsonString(search.query)), type: ISSUE, first: \(pageSize)\(after)) {
                  issueCount
                  pageInfo { hasNextPage endCursor }
                  ...\(fragmentName(for: search.content))
                }
            """
        }

        // Only the fragments something asks for: GraphQL rejects a document
        // that declares one nothing uses.
        var fragments: [String] = []
        if searches.contains(where: { $0.content == .pullRequests }) {
            fragments.append(PullRequestQuery.pullRequestFragment)
        }
        if searches.contains(where: { $0.content == .issues }) {
            fragments.append(IssueQuery.fragment)
        }

        return """
        query {
          # Free: asking for the allowance does not spend any of it.
          rateLimit { limit remaining resetAt }
        \(aliases.joined(separator: "\n"))
        }

        \(fragments.joined(separator: "\n\n"))
        """
    }

    static func alias(_ index: Int) -> String { "s\(index)" }

    static func fragmentName(for content: ListContent) -> String {
        switch content {
        case .pullRequests: "Results"
        case .issues: "IssueResults"
        }
    }
}

/// What one refresh brought back, per list.
public struct ListResults: Sendable {
    public var pullRequests: [String: [PullRequestItem]]
    public var issues: [String: [IssueItem]]
    /// How many GitHub says match, per list. Summed across a list's
    /// searches, so where two of them overlap this is above the number of
    /// rows -- which is why it is not on its own a measure of what is
    /// missing. See `unread(stoppedAt:)`.
    public var totals: [String: Int]

    public init(
        pullRequests: [String: [PullRequestItem]] = [:],
        issues: [String: [IssueItem]] = [:],
        totals: [String: Int] = [:]
    ) {
        self.pullRequests = pullRequests
        self.issues = issues
        self.totals = totals
    }

    /// How many rows one list has collected so far.
    public func count(in listID: String) -> Int {
        (pullRequests[listID]?.count ?? 0) + (issues[listID]?.count ?? 0)
    }

    /// How many rows a list is not showing, per list.
    ///
    /// Only for lists where paging stopped at the cap. Two things make the
    /// arithmetic alone a lie: several searches can feed one list and their
    /// counts add up while their rows are de-duplicated, and GitHub counts
    /// at the moment it is asked, so a pull request merged between the count
    /// and the page leaves the total one above what arrived. Either would
    /// have a complete list announce rows that are not missing.
    public func unread(stoppedAt caps: Set<String>) -> [String: Int] {
        var unread: [String: Int] = [:]
        for listID in caps {
            guard let total = totals[listID] else { continue }
            let missing = total - count(in: listID)
            if missing > 0 { unread[listID] = missing }
        }
        return unread
    }

    /// Takes in another page, keeping the order it arrived in and dropping
    /// anything already held: two searches feeding one list will return the
    /// same pull request, and so will a page that overlaps the one before.
    public mutating func absorb(_ page: ListResults) {
        for (listID, items) in page.pullRequests {
            var seen = Set(pullRequests[listID]?.map(\.id) ?? [])
            pullRequests[listID, default: []] += items.filter { seen.insert($0.id).inserted }
        }
        for (listID, items) in page.issues {
            var seen = Set(issues[listID]?.map(\.id) ?? [])
            issues[listID, default: []] += items.filter { seen.insert($0.id).inserted }
        }
    }
}

/// Where one search stands after a page: what is left to ask for, and how
/// many there are altogether.
public struct ListPage: Sendable {
    public let cursor: String?
    public let total: Int

    public init(cursor: String?, total: Int) {
        self.cursor = cursor
        self.total = total
    }
}

/// Reads the aliased searches back apart.
public enum ListParser {
    /// Merges every search of a list into one result, keeping the first of
    /// any duplicate.
    ///
    /// Lists do overlap by design: a pull request can be requested from
    /// someone personally and through a team, and it is one row either way.
    public static func results(
        from payload: [String: Any], searches: [ListSearch], viewer: String? = nil
    ) -> ListResults {
        var results = ListResults()
        var seen: [String: Set<String>] = [:]

        for (index, search) in searches.enumerated() {
            guard
                let node = payload[ListQuery.alias(index)] as? [String: Any],
                let nodes = node["nodes"] as? [[String: Any]]
            else { continue }

            // Several searches can feed one list, so the totals add up the
            // way the rows do.
            if let total = node["issueCount"] as? Int {
                results.totals[search.listID, default: 0] += total
            }

            switch search.content {
            case .pullRequests:
                for item in nodes.compactMap({ PullRequestParser.pullRequest(from: $0, requestedOf: viewer) }) {
                    guard seen[search.listID, default: []].insert(item.id).inserted else { continue }
                    results.pullRequests[search.listID, default: []].append(item)
                }
            case .issues:
                for item in nodes.compactMap(IssueParser.issue(from:)) {
                    guard seen[search.listID, default: []].insert(item.id).inserted else { continue }
                    results.issues[search.listID, default: []].append(item)
                }
            }
        }

        // A list that ran and found nothing has an empty result rather than
        // none: the difference is between "nothing there" and "never asked".
        for search in searches where results.pullRequests[search.listID] == nil
            && results.issues[search.listID] == nil
        {
            switch search.content {
            case .pullRequests: results.pullRequests[search.listID] = []
            case .issues: results.issues[search.listID] = []
            }
        }

        return results
    }

    /// Where each search stands: the cursor to carry on from, and how many
    /// there are in total.
    public static func pages(
        from payload: [String: Any], searches: [ListSearch]
    ) -> [Int: ListPage] {
        var pages: [Int: ListPage] = [:]
        for index in searches.indices {
            guard let node = payload[ListQuery.alias(index)] as? [String: Any] else { continue }
            let info = node["pageInfo"] as? [String: Any]
            let more = info?["hasNextPage"] as? Bool ?? false
            pages[index] = ListPage(
                cursor: more ? info?["endCursor"] as? String : nil,
                total: node["issueCount"] as? Int ?? 0
            )
        }
        return pages
    }

    /// What GitHub said was left, as it travels with every list refresh.
    public static func budget(from payload: [String: Any]) -> RateBudget? {
        guard
            let node = payload["rateLimit"] as? [String: Any],
            let remaining = node["remaining"] as? Int,
            let limit = node["limit"] as? Int
        else { return nil }
        return RateBudget(
            remaining: remaining,
            limit: limit,
            resetAt: GitHubDate.optional(from: node["resetAt"] as? String)
        )
    }
}
