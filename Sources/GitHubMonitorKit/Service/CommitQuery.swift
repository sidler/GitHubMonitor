import Foundation

/// Reading the commits behind a pull request.
///
/// Asked for separately and only when somebody opens the section. The
/// count beside the other numbers comes free with the detail -- one more
/// field in a request already being made -- and that is what the section
/// can be shut by default without being useless: it says how many there
/// are before it has read a single one.
public enum CommitQuery {
    /// How many to ask for.
    ///
    /// `last:` rather than `first:`, so a pull request with three hundred
    /// commits gives up its newest fifty rather than the fifty it started
    /// with. What is missing is then the oldest, which is the half nobody
    /// scrolls to.
    public static let pageSize = 50

    public static let document = """
    query($id: ID!) {
      node(id: $id) {
        ... on PullRequest {
          commits(last: \(pageSize)) {
            totalCount
            nodes {
              commit {
                oid
                abbreviatedOid
                messageHeadline
                committedDate
                commitUrl
                author { name user { login avatarUrl } }
                statusCheckRollup { state }
              }
            }
          }
        }
      }
    }
    """

    /// The commits, newest first.
    ///
    /// GitHub hands them over oldest first, which is how a branch was
    /// written. This list is read by somebody coming back to a pull
    /// request they have seen before, and their question is what has
    /// arrived since -- so it is turned around, and every other list in
    /// this app is newest first anyway.
    public static func commits(from payload: [String: Any]) throws -> [PullRequestCommit] {
        guard
            let node = payload["node"] as? [String: Any],
            let container = node["commits"] as? [String: Any]
        else {
            throw GitHubError.decoding("pull request has no commits")
        }

        let nodes = container["nodes"] as? [[String: Any]] ?? []
        return nodes
            .compactMap { entry -> PullRequestCommit? in
                guard
                    let commit = entry["commit"] as? [String: Any],
                    let oid = commit["oid"] as? String
                else { return nil }

                let author = commit["author"] as? [String: Any] ?? [:]
                let user = author["user"] as? [String: Any]
                return PullRequestCommit(
                    oid: oid,
                    abbreviated: commit["abbreviatedOid"] as? String,
                    headline: commit["messageHeadline"] as? String ?? "",
                    // The account where there is one, and the name
                    // written into the commit otherwise: a commit by
                    // somebody without a GitHub account is still a commit
                    // by somebody.
                    author: (user?["login"] as? String)
                        ?? (author["name"] as? String ?? ""),
                    avatarURL: (user?["avatarUrl"] as? String).flatMap(URL.init(string:)),
                    committedAt: GitHubDate.date(
                        from: commit["committedDate"] as? String, fallback: .distantPast
                    ),
                    checks: status(of: commit),
                    url: (commit["commitUrl"] as? String).flatMap(URL.init(string:))
                )
            }
            .reversed()
    }

    /// What this commit's own checks came to.
    ///
    /// The rollup's one word, not the list of contexts the detail query
    /// reads: a row has space for a mark, and anybody who wants to know
    /// which check failed is one click from the commit on GitHub.
    static func status(of commit: [String: Any]) -> ChecksStatus {
        guard
            let rollup = commit["statusCheckRollup"] as? [String: Any],
            let state = rollup["state"] as? String
        else { return .none }

        switch state {
        case "SUCCESS": return .success
        case "FAILURE", "ERROR": return .failure
        case "PENDING", "EXPECTED": return .pending
        default: return .none
        }
    }
}
