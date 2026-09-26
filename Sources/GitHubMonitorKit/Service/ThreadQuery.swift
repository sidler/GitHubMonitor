import Foundation

/// The conversation behind a notification.
///
/// A mention is almost never in the issue's description -- it is in a
/// comment somebody wrote. The pane used to show only the one comment the
/// notification pointed at, which for a thread with no comments is the
/// description itself, so the sentence that named you was often nowhere on
/// screen.
public enum ThreadQuery {
    /// How much of the conversation the pane shows. The end of it: a long
    /// thread is read on GitHub, and what was said last is what the
    /// notification is about.
    public static let commentLimit = 20

    /// The repository and number a notification's subject URL points at.
    ///
    /// The notifications API hands out REST URLs -- `.../repos/o/r/issues/7`
    /// or `.../pulls/7` -- and GraphQL wants the pieces.
    public static func subject(from url: URL) -> (owner: String, name: String, number: Int)? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard
            let reposIndex = parts.firstIndex(of: "repos"),
            parts.count >= reposIndex + 5,
            let number = Int(parts[reposIndex + 4])
        else { return nil }
        return (parts[reposIndex + 1], parts[reposIndex + 2], number)
    }

    /// One document for both kinds: a mention can be on an issue or on a
    /// pull request, and by the time it arrives nothing says which.
    public static let document = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        issueOrPullRequest(number: $number) {
          ... on Issue {
            body
            comments(last: \(commentLimit)) {
              totalCount
              nodes { id createdAt body author { login avatarUrl } }
            }
          }
          ... on PullRequest {
            body
            comments(last: \(commentLimit)) {
              totalCount
              nodes { id createdAt body author { login avatarUrl } }
            }
          }
        }
      }
    }
    """

    public static func thread(from payload: [String: Any]) throws -> IssueDetail {
        guard
            let repository = payload["repository"] as? [String: Any],
            let node = repository["issueOrPullRequest"] as? [String: Any]
        else {
            throw GitHubError.decoding("conversation not found")
        }

        let comments = node["comments"] as? [String: Any]
        let nodes = comments?["nodes"] as? [[String: Any]] ?? []

        return IssueDetail(
            body: node["body"] as? String ?? "",
            comments: nodes.compactMap(IssueQuery.comment(from:)),
            totalComments: comments?["totalCount"] as? Int ?? nodes.count
        )
    }
}

public extension IssueComment {
    /// Whether this comment is the one that named you.
    ///
    /// Plain text matching, because that is what a mention is: `@login` in
    /// the body. Case-insensitive, and only where the name ends -- `@sid`
    /// must not match `@avery`.
    func mentions(_ login: String) -> Bool {
        guard !login.isEmpty else { return false }
        let needle = "@\(login)".lowercased()
        let text = body.lowercased()
        var index = text.startIndex

        while let range = text.range(of: needle, range: index..<text.endIndex) {
            let after = range.upperBound
            if after == text.endIndex || !(text[after].isLetter || text[after].isNumber
                || text[after] == "-" || text[after] == "/")
            {
                return true
            }
            index = after
        }
        return false
    }
}
