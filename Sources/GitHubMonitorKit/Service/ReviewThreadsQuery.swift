import Foundation

/// The conversations hanging off a pull request's diff.
///
/// GraphQL rather than REST: `/pulls/{n}/comments` gives a flat list that
/// has to be stitched back into threads by `in_reply_to_id`, and says
/// nothing about whether a thread was resolved. `reviewThreads` is already
/// the shape the diff draws.
public enum ReviewThreadsQuery {
    /// GitHub's most per page.
    public static let pageSize = 100

    /// Enough threads for any review a person reads in one sitting. A diff
    /// with more conversations than this is one to have in a browser.
    public static let maximumThreads = 300

    /// Comments within one thread. A thread this long stopped being a
    /// remark on a line some time ago.
    public static let commentLimit = 25

    public static let document = """
    query($id: ID!, $after: String) {
      rateLimit { limit remaining resetAt cost }
      node(id: $id) {
        ... on PullRequest {
          reviewThreads(first: \(pageSize), after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              path
              line
              originalLine
              diffSide
              isResolved
              isOutdated
              comments(first: \(commentLimit)) {
                # The hunk only off the first one: every comment in a
                # thread carries the same few lines, and they are the
                # longest field in this document.
                nodes { id createdAt body diffHunk author { login avatarUrl } }
              }
            }
          }
        }
      }
    }
    """

    /// One page of threads, and where to carry on from.
    public static func page(
        from payload: [String: Any]
    ) -> (threads: [ReviewThread], cursor: String?) {
        guard
            let node = payload["node"] as? [String: Any],
            let container = node["reviewThreads"] as? [String: Any],
            let nodes = container["nodes"] as? [[String: Any]]
        else { return ([], nil) }

        let threads = nodes.compactMap(thread(from:))
        let info = container["pageInfo"] as? [String: Any]
        let more = info?["hasNextPage"] as? Bool ?? false
        return (threads, more ? info?["endCursor"] as? String : nil)
    }

    static func thread(from node: [String: Any]) -> ReviewThread? {
        guard let id = node["id"] as? String, let path = node["path"] as? String else {
            return nil
        }

        let comments = (node["comments"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        // A thread whose every comment was deleted is a row with nothing in
        // it, and the diff is better off without the gap.
        let read = comments.compactMap(IssueQuery.comment(from:))
        guard !read.isEmpty else { return nil }

        let isOutdated = node["isOutdated"] as? Bool ?? false
        return ReviewThread(
            id: id,
            path: path,
            // `line` is where the thread is now; `originalLine` is where
            // it was written. Only the first matches the patch on screen.
            // The second is kept for the threads that have lost the first
            // -- it places them near rather than on, and the hunk they
            // carry is what keeps that honest: the reader is shown the
            // code the remark was about instead of being left to assume
            // it was about whatever ended up next to it.
            line: node["line"] as? Int,
            side: ReviewThread.Side(apiValue: node["diffSide"] as? String),
            isResolved: node["isResolved"] as? Bool ?? false,
            isOutdated: isOutdated,
            comments: read,
            originalLine: node["originalLine"] as? Int,
            hunk: comments.first?["diffHunk"] as? String
        )
    }
}
