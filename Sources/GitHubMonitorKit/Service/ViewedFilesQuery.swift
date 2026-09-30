import Foundation

/// Which files of a pull request this person has ticked off, and the two
/// mutations that set the tick.
///
/// GraphQL rather than REST, because this is the one thing about a changed
/// file that REST does not carry: `/pulls/{n}/files` has the patch and no
/// viewed state, `files` in GraphQL has the viewed state and no patch. So
/// the two are fetched separately and joined on the path -- which is what
/// both sides key on anyway.
public enum ViewedFilesQuery {
    /// GitHub's most per page.
    public static let pageSize = 100

    /// The same ceiling the patches stop at. Asking about files the overlay
    /// will not show would be paying for an answer nobody reads.
    public static var maximumFiles: Int { ChangedFilesQuery.maximumFiles }

    public static let document = """
    query($id: ID!, $after: String) {
      rateLimit { limit remaining resetAt cost }
      node(id: $id) {
        ... on PullRequest {
          files(first: \(pageSize), after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
              path
              viewerViewedState
            }
          }
        }
      }
    }
    """

    /// One page of states, and where to carry on from.
    public static func page(
        from payload: [String: Any]
    ) -> (states: [String: FileViewedState], cursor: String?) {
        guard
            let node = payload["node"] as? [String: Any],
            let files = node["files"] as? [String: Any],
            let nodes = files["nodes"] as? [[String: Any]]
        else { return ([:], nil) }

        var states: [String: FileViewedState] = [:]
        for entry in nodes {
            guard let path = entry["path"] as? String else { continue }
            states[path] = FileViewedState(apiValue: entry["viewerViewedState"] as? String)
        }

        let info = files["pageInfo"] as? [String: Any]
        let more = info?["hasNextPage"] as? Bool ?? false
        return (states, more ? info?["endCursor"] as? String : nil)
    }

    /// Setting the tick. Two mutations rather than one with a flag, because
    /// that is how GitHub models it.
    public static let markDocument = """
    mutation($id: ID!, $path: String!) {
      markFileAsViewed(input: { pullRequestId: $id, path: $path }) {
        clientMutationId
      }
    }
    """

    public static let unmarkDocument = """
    mutation($id: ID!, $path: String!) {
      unmarkFileAsViewed(input: { pullRequestId: $id, path: $path }) {
        clientMutationId
      }
    }
    """

    public static func document(setting viewed: Bool) -> String {
        viewed ? markDocument : unmarkDocument
    }
}
