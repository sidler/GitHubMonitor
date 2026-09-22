import Foundation

/// Builds the GitHub search queries and the GraphQL document behind the
/// "reviews requested" list.
///
/// GitHub's search syntax treats repeated qualifiers of the same kind as AND,
/// so `review-requested:me team-review-requested:org/team` would find nothing.
/// Each audience therefore needs its own search, and GraphQL lets us alias
/// them into a single request rather than paying a round trip each.
public enum PullRequestQuery {
    public static let pageSize = 50

    /// Pull requests the user opened that are still open — the ones they are
    /// waiting on other people for.
    public static func authoredQuery(login: String, repositoryFilters: [String]) -> String {
        "is:pr is:open archived:false author:\(login)" + repositoryScope(repositoryFilters)
    }

    /// Every open pull request in one repository, for the dashboard.
    /// Drafts included: the chart reports them as their own segment.
    public static func repositoryQuery(_ repository: String) -> String {
        "is:pr is:open archived:false repo:\(repository.trimmingCharacters(in: .whitespaces))"
    }

    /// The dashboard's own document.
    ///
    /// Carries reviewer fields the other lists do not need. They are nested
    /// connections, so putting them in the shared fragment would make every
    /// refresh pay for data only this view reads.
    public static func repositoryDocument(_ repository: String) -> String {
        """
        query {
          d0: search(query: \(jsonString(repositoryQuery(repository))), type: ISSUE, first: 100) {
            nodes {
              ... on PullRequest {
                id
                number
                title
                isDraft
                createdAt
                updatedAt
                url
                reviewDecision
                repository { nameWithOwner }
                author { login avatarUrl }
                commits(last: 1) {
                  nodes { commit { statusCheckRollup { state } } }
                }
                latestReviews(first: 25) {
                  nodes {
                    state
                    author { login avatarUrl }
                  }
                }
                reviewRequests(first: 25) {
                  totalCount
                  nodes {
                    requestedReviewer {
                      ... on User { login avatarUrl }
                      ... on Team { name }
                    }
                  }
                }
              }
            }
          }
        }
        """
    }

    /// One search string per audience whose review requests count as the
    /// user's own.
    public static func searchQueries(
        login: String,
        teamSlugs: [String],
        repositoryFilters: [String]
    ) -> [String] {
        let scope = repositoryScope(repositoryFilters)
        let base = "is:pr is:open archived:false"

        var queries = ["\(base) review-requested:\(login)\(scope)"]
        for slug in normalisedTeams(teamSlugs) {
            queries.append("\(base) team-review-requested:\(slug)\(scope)")
        }
        return queries
    }

    /// Repository filters as search qualifiers. Unlike review qualifiers,
    /// repeated `repo:`/`org:` terms are OR-ed by GitHub, so they can all go
    /// into the same query.
    static func repositoryScope(_ filters: [String]) -> String {
        let terms = filters
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.contains("/") ? "repo:\($0)" : "org:\($0)" }
        return terms.isEmpty ? "" : " " + terms.joined(separator: " ")
    }

    /// Team slugs as GitHub expects them: `org/team`, lower-cased, without a
    /// leading `@`.
    static func normalisedTeams(_ slugs: [String]) -> [String] {
        slugs
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    .lowercased()
            }
            .filter { $0.contains("/") && !$0.hasPrefix("/") && !$0.hasSuffix("/") }
    }

    /// Prefix marking the aliases of a group of searches, so one document can
    /// carry several lists and the parser can tell them apart.
    public enum Group: String, CaseIterable, Sendable {
        case reviewRequested = "r"
        case authored = "a"
        /// Issues assigned to the user. Search returns them from the same
        /// `ISSUE` type as pull requests, but they carry different fields.
        case issues = "i"

        /// Which set of fields the searches in this group ask for.
        var fragment: String {
            switch self {
            case .reviewRequested, .authored: "Results"
            case .issues: "IssueResults"
            }
        }
    }

    /// A single GraphQL document running every search under its own alias.
    ///
    /// Every list travels in one request: further round trips would multiply
    /// the latency of a refresh for no benefit, since the lists are always
    /// wanted together -- and the menu bar counts all of them, so none of
    /// them may be a refresh behind the others.
    public static func document(
        reviewRequested: [String],
        authored: [String],
        issues: [String] = []
    ) -> String {
        let groups: [Group: [String]] = [
            .reviewRequested: reviewRequested,
            .authored: authored,
            .issues: issues,
        ]
        let searches = groups
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .flatMap { group, queries in
                queries.enumerated().map { index, query in
                    """
                        \(group.rawValue)\(index): search(query: \(jsonString(query)), type: ISSUE, first: \(pageSize)) {
                          ...\(group.fragment)
                        }
                    """
                }
            }
            .joined(separator: "\n")

        // Only the fragments something asks for: GraphQL rejects a document
        // that declares one nothing uses, so an empty list would otherwise
        // fail the whole refresh.
        var fragments: [String] = []
        if !reviewRequested.isEmpty || !authored.isEmpty { fragments.append(pullRequestFragment) }
        if !issues.isEmpty { fragments.append(IssueQuery.fragment) }

        return """
        query {
        \(searches)
        }

        \(fragments.joined(separator: "\n\n"))
        """
    }

    static let pullRequestFragment = """
    fragment Results on SearchResultItemConnection {
      nodes {
        ... on PullRequest {
          id
          number
          title
          isDraft
          createdAt
          updatedAt
          url
          reviewDecision
          repository { nameWithOwner }
          author { login avatarUrl }
          commits(last: 1) {
            nodes { commit { statusCheckRollup { state } } }
          }
          # One entry per reviewer who has an opinion, so these are people
          # rather than review events. Ten of them: a pull request with
          # more approvals than that does not exist here, and every extra
          # node is charged against the hourly GraphQL budget on every
          # refresh of every list.
          latestOpinionatedReviews(first: 10) {
            nodes { state }
          }
          # Outstanding requests are a plain count, which costs nothing.
          reviewRequests { totalCount }
        }
      }
    }
    """

    /// Escapes a Swift string for embedding in a GraphQL document.
    static func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        guard
            let data,
            let array = String(data: data, encoding: .utf8),
            array.count >= 2
        else {
            return "\"\(value)\""
        }
        // Strip the enclosing brackets of the one-element array.
        return String(array.dropFirst().dropLast())
    }
}
