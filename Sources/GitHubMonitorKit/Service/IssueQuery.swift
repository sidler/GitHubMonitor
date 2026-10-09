import Foundation

/// The search and the fields behind the "My Issues" list.
///
/// Issues travel in the same request as the two pull request lists rather
/// than in one of their own: the menu bar counts them, so they have to be as
/// fresh as the rest, and a separate round trip would make every refresh
/// slower for data that is one more alias in a document already being sent.
public enum IssueQuery {
    /// Ten labels and no more: rows show what fits on one line, and the
    /// browser is a click away for an issue that carries more.
    public static let labelLimit = 10

    /// The fields the list reads, as a fragment the shared document can use
    /// under each of its issue aliases.
    public static let fragment = """
    fragment IssueResults on SearchResultItemConnection {
      nodes {
        ... on Issue {
          id
          number
          title
          createdAt
          updatedAt
          url
          repository { nameWithOwner }
          author { login avatarUrl }
          # A count, not the comments themselves: the bodies are fetched for
          # the one issue whose detail pane is open.
          comments { totalCount }
          milestone { title }
          # The organisation's own types -- Bug, Task, Feature, Epic. Null
          # where none is set, and where the organisation defines none.
          issueType { name color }
          labels(first: \(labelLimit)) { nodes { name color } }
          # The pull requests that answer it. Closed and merged ones
          # included on purpose: GitHub leaves them out by default, and the
          # merged one is usually the one being looked for.
          closedByPullRequestsReferences(
            first: \(ItemLinkParser.limit), includeClosedPrs: true
          ) {
            totalCount
            nodes {
              number
              title
              url
              # Free: these nodes are already being fetched, and without
              # them the list can say a pull request answers the issue but
              # not whether anybody has merged it.
              state
              isDraft
              repository { nameWithOwner }
            }
          }
        }
      }
    }
    """

    /// The detail pane's own request: the issue's text and the end of its
    /// thread, for one issue at a time.
    public static let detailDocument = """
    query($id: ID!) {
      node(id: $id) {
        ... on Issue {
          body
          comments(last: \(commentLimit)) {
            totalCount
            nodes {
              id
              createdAt
              body
              author { login avatarUrl }
            }
          }
        }
      }
    }
    """

    /// How much of the thread the pane shows. The last ten: a long
    /// discussion is read on GitHub, and what was said most recently is what
    /// decides whether this issue needs attention now.
    public static let commentLimit = 10

    public static func detail(from payload: [String: Any]) throws -> IssueDetail {
        guard let node = payload["node"] as? [String: Any] else {
            throw GitHubError.decoding("issue not found")
        }

        let comments = node["comments"] as? [String: Any]
        let nodes = comments?["nodes"] as? [[String: Any]] ?? []

        return IssueDetail(
            body: node["body"] as? String ?? "",
            comments: nodes.compactMap(comment(from:)),
            totalComments: comments?["totalCount"] as? Int ?? nodes.count
        )
    }

    static func comment(from node: [String: Any]) -> IssueComment? {
        guard let id = node["id"] as? String else { return nil }
        let author = node["author"] as? [String: Any]
        return IssueComment(
            id: id,
            // A deleted account leaves the author null rather than absent.
            author: author?["login"] as? String ?? "ghost",
            avatarURL: (author?["avatarUrl"] as? String).flatMap(URL.init(string:)),
            createdAt: GitHubDate.date(from: node["createdAt"] as? String),
            body: node["body"] as? String ?? ""
        )
    }
}

/// Reads one issue out of a search result.
public enum IssueParser {
    static func issue(from node: [String: Any]) -> IssueItem? {
        // Search hits that are not issues come back as empty objects.
        guard
            let id = node["id"] as? String,
            let number = node["number"] as? Int,
            let title = node["title"] as? String,
            let urlString = node["url"] as? String,
            let url = URL(string: urlString)
        else { return nil }

        let author = node["author"] as? [String: Any]
        let repository = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? "?"

        // Only what GitHub links. An issue title does not carry a pull
        // request number the way a pull request title carries an issue's,
        // so there is nothing to read off the front of it.
        let recorded = ItemLinkParser.links(
            from: node, key: "closedByPullRequestsReferences", fallbackRepository: repository
        )

        return IssueItem(
            id: id,
            number: number,
            title: title,
            repository: repository,
            author: author?["login"] as? String ?? "ghost",
            authorAvatarURL: (author?["avatarUrl"] as? String).flatMap(URL.init(string:)),
            url: url,
            createdAt: GitHubDate.date(from: node["createdAt"] as? String),
            updatedAt: GitHubDate.date(from: node["updatedAt"] as? String),
            comments: (node["comments"] as? [String: Any])?["totalCount"] as? Int ?? 0,
            labels: labels(from: node),
            milestone: (node["milestone"] as? [String: Any])?["title"] as? String,
            type: type(from: node),
            links: recorded.links,
            linkedTotal: recorded.total
        )
    }

    static func type(from node: [String: Any]) -> IssueType? {
        guard
            let type = node["issueType"] as? [String: Any],
            let name = type["name"] as? String
        else { return nil }
        return IssueType(name: name, color: IssueTypeColor(apiValue: type["color"] as? String))
    }

    static func labels(from node: [String: Any]) -> [IssueLabel] {
        let nodes = (node["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        return nodes.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            return IssueLabel(name: name, color: entry["color"] as? String ?? "")
        }
    }
}
