import Foundation

/// Fetches and parses the extra detail shown for one pull request.
///
/// Deliberately a separate request rather than extra fields on the list
/// query: checks, reviewers and review requests are all nested connections,
/// and asking for them across every pull request in the queue would multiply
/// the GraphQL cost of a refresh for data the user sees one row at a time.
public enum PullRequestDetailQuery {
    public static let document = """
    query($id: ID!) {
      node(id: $id) {
        ... on PullRequest {
          headRefName
          baseRefName
          additions
          deletions
          changedFiles
          comments { totalCount }
          body
          mergeable
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup {
                  contexts(first: 100) {
                    nodes {
                      ... on CheckRun { id name conclusion status }
                      ... on StatusContext { id context state }
                    }
                  }
                }
              }
            }
          }
          latestReviews(first: 25) {
            nodes {
              state
              author { login avatarUrl }
            }
          }
          reviewRequests(first: 25) {
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
    """

    public static func detail(from payload: [String: Any]) throws -> PullRequestDetail {
        guard let node = payload["node"] as? [String: Any] else {
            throw GitHubError.decoding("pull request not found")
        }

        return PullRequestDetail(
            headBranch: node["headRefName"] as? String ?? "",
            baseBranch: node["baseRefName"] as? String ?? "",
            additions: node["additions"] as? Int ?? 0,
            deletions: node["deletions"] as? Int ?? 0,
            changedFiles: node["changedFiles"] as? Int ?? 0,
            comments: (node["comments"] as? [String: Any])?["totalCount"] as? Int ?? 0,
            body: node["body"] as? String ?? "",
            mergeStatus: PullRequestParser.mergeStatus(node["mergeable"] as? String),
            checks: checks(from: node),
            reviewers: reviewers(from: node)
        )
    }

    // MARK: - Checks

    static func checks(from node: [String: Any]) -> [CheckRun] {
        guard
            let commits = node["commits"] as? [String: Any],
            let commitNodes = commits["nodes"] as? [[String: Any]],
            let commit = commitNodes.first?["commit"] as? [String: Any],
            let rollup = commit["statusCheckRollup"] as? [String: Any],
            let contexts = rollup["contexts"] as? [String: Any],
            let nodes = contexts["nodes"] as? [[String: Any]]
        else { return [] }

        return nodes.compactMap(check(from:))
            // Failures first: they are the reason to look at this list.
            .sorted { lhs, rhs in
                lhs.status == rhs.status
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : priority(lhs.status) < priority(rhs.status)
            }
            // Belt as well as braces: GitHub's ids are distinct, but an
            // answer that somehow repeats one must not reach a list that
            // keys on it.
            .uniquedByID()
    }

    private static func priority(_ status: ChecksStatus) -> Int {
        switch status {
        case .failure: 0
        case .pending: 1
        case .success: 2
        case .none: 3
        }
    }

    static func check(from node: [String: Any]) -> CheckRun? {
        // A CheckRun carries name/conclusion; a StatusContext context/state.
        if let name = node["name"] as? String {
            // A run still in flight has no conclusion yet.
            let status: ChecksStatus = if node["status"] as? String == "COMPLETED" {
                checkConclusion(node["conclusion"] as? String)
            } else {
                .pending
            }
            return CheckRun(id: node["id"] as? String, name: name, status: status)
        }
        if let context = node["context"] as? String {
            return CheckRun(
                id: node["id"] as? String,
                name: context,
                status: statusContextState(node["state"] as? String)
            )
        }
        return nil
    }

    static func checkConclusion(_ raw: String?) -> ChecksStatus {
        switch raw {
        case "SUCCESS": .success
        case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE": .failure
        // Cancelled, skipped, neutral and action-required are not failures
        // and should not be reported as such.
        default: .none
        }
    }

    static func statusContextState(_ raw: String?) -> ChecksStatus {
        switch raw {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING": .pending
        default: .none
        }
    }

    // MARK: - Reviewers

    static func reviewers(from node: [String: Any]) -> [ReviewerStatus] {
        var result: [ReviewerStatus] = []
        var seen = Set<String>()

        if
            let reviews = node["latestReviews"] as? [String: Any],
            let nodes = reviews["nodes"] as? [[String: Any]]
        {
            for review in nodes {
                let author = review["author"] as? [String: Any]
                guard let login = author?["login"] as? String else { continue }
                let status = ReviewerStatus(
                    name: login,
                    avatarURL: (author?["avatarUrl"] as? String).flatMap(URL.init(string:)),
                    state: ReviewState(apiValue: review["state"] as? String),
                    isTeam: false
                )
                if seen.insert(status.id).inserted { result.append(status) }
            }
        }

        if
            let requests = node["reviewRequests"] as? [String: Any],
            let nodes = requests["nodes"] as? [[String: Any]]
        {
            for request in nodes {
                guard let reviewer = request["requestedReviewer"] as? [String: Any] else { continue }
                let status: ReviewerStatus
                if let login = reviewer["login"] as? String {
                    status = ReviewerStatus(
                        name: login,
                        avatarURL: (reviewer["avatarUrl"] as? String).flatMap(URL.init(string:)),
                        state: .pending,
                        isTeam: false
                    )
                } else if let team = reviewer["name"] as? String {
                    status = ReviewerStatus(name: team, avatarURL: nil, state: .pending, isTeam: true)
                } else {
                    continue
                }
                // Someone who already reviewed and was asked again appears in
                // both lists; the review they left is the more useful state.
                if seen.insert(status.id).inserted { result.append(status) }
            }
        }

        return ReviewerStatus.ordered(result)
    }
}
