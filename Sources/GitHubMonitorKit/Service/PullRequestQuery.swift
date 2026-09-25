import Foundation

/// The pieces the list searches are built from: the fields a pull request
/// row needs, the repository scope, and the dashboard's own query.
///
/// The lists themselves are written by the user now; what is left here is
/// what they are assembled with. GitHub's search syntax reads repeated
/// qualifiers of one kind as AND, which is why a list can hold several
/// searches rather than one.
public enum PullRequestQuery {

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
          # Worked out in the background by GitHub: a pull request opened a
          # moment ago answers UNKNOWN and carries a real answer on a later
          # refresh, which is why nothing is drawn for that case.
          mergeable
          # What approving from here needs to know before it offers to.
          # All four are plain fields on the pull request, so the search
          # still costs one point.
          headRefOid
          viewerDidAuthor
          viewerLatestReview { state submittedAt }
          autoMergeRequest { enabledAt }
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
          # When the review was asked of this person, which is the only
          # honest answer to "how long has this been waiting on me". The
          # last ten: a pull request re-requested more often than that has
          # other problems. Measured against the API, this connection adds
          # nothing to the cost -- a search is one point whatever it
          # carries back per node.
          timelineItems(last: 10, itemTypes: [REVIEW_REQUESTED_EVENT]) {
            nodes {
              ... on ReviewRequestedEvent {
                createdAt
                requestedReviewer { ... on User { login } }
              }
            }
          }
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
