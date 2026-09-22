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
    /// Expands to one search per configured team. GitHub understands `@me`
    /// itself, but a team qualifier takes one slug, and repeated qualifiers
    /// of a kind are read as AND -- so several teams mean several searches.
    public static let teamsPlaceholder = "@myteams"

    /// The searches one list runs, after the placeholder and the global
    /// repository filter have been applied.
    public static func searches(
        for list: SavedList,
        teamSlugs: [String],
        repositoryFilters: [String]
    ) -> [ListSearch] {
        list.queryLines
            .flatMap { expand($0, teamSlugs: teamSlugs) }
            .map { query in
                ListSearch(
                    listID: list.id,
                    content: list.content,
                    query: scoped(query, repositoryFilters: repositoryFilters)
                )
            }
    }

    /// With no teams configured the line is dropped rather than run with the
    /// placeholder still in it: `team-review-requested:@myteams` is not a
    /// search GitHub understands, and dropping the qualifier instead would
    /// turn one line into "every pull request there is".
    static func expand(_ line: String, teamSlugs: [String]) -> [String] {
        guard line.contains(teamsPlaceholder) else { return [line] }
        return PullRequestQuery.normalisedTeams(teamSlugs).map {
            line.replacingOccurrences(of: teamsPlaceholder, with: $0)
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

    public static let pageSize = 50

    /// Every search in one request, each under its own alias.
    ///
    /// One document rather than one per list: a refresh that fired a request
    /// per list would take as long as the slowest sum of them, and the menu
    /// bar would count lists from different moments.
    public static func document(_ searches: [ListSearch]) -> String {
        let aliases = searches.enumerated().map { index, search in
            """
                \(alias(index)): search(query: \(PullRequestQuery.jsonString(search.query)), type: ISSUE, first: \(pageSize)) {
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

    public init(
        pullRequests: [String: [PullRequestItem]] = [:],
        issues: [String: [IssueItem]] = [:]
    ) {
        self.pullRequests = pullRequests
        self.issues = issues
    }
}

/// Reads the aliased searches back apart.
public enum ListParser {
    /// Merges every search of a list into one result, keeping the first of
    /// any duplicate.
    ///
    /// Lists do overlap by design: a pull request can be requested from
    /// someone personally and through a team, and it is one row either way.
    public static func results(from payload: [String: Any], searches: [ListSearch]) -> ListResults {
        var results = ListResults()
        var seen: [String: Set<String>] = [:]

        for (index, search) in searches.enumerated() {
            guard
                let node = payload[ListQuery.alias(index)] as? [String: Any],
                let nodes = node["nodes"] as? [[String: Any]]
            else { continue }

            switch search.content {
            case .pullRequests:
                for item in nodes.compactMap(PullRequestParser.pullRequest(from:)) {
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
}
