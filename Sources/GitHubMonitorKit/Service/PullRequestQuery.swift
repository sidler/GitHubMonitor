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

    /// A single GraphQL document running every search under its own alias.
    public static func document(for queries: [String]) -> String {
        let searches = queries.enumerated().map { index, query in
            """
                s\(index): search(query: \(jsonString(query)), type: ISSUE, first: \(pageSize)) {
                  ...Results
                }
            """
        }.joined(separator: "\n")

        return """
        query {
        \(searches)
        }

        fragment Results on SearchResultItemConnection {
          nodes {
            ... on PullRequest {
              id
              number
              title
              isDraft
              updatedAt
              url
              reviewDecision
              repository { nameWithOwner }
              author { login avatarUrl }
              commits(last: 1) {
                nodes { commit { statusCheckRollup { state } } }
              }
            }
          }
        }
        """
    }

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
