import Foundation

/// Turns the GraphQL payload into model objects.
///
/// Kept separate from the client so it can be tested against recorded
/// responses without a network.
public enum PullRequestParser {
    /// Reads every aliased search in the payload and merges them.
    ///
    /// A pull request can be requested from the user personally *and* from one
    /// of their teams, so the same item may appear in more than one search;
    /// deduplicating by id is what keeps the count honest.
    public static func pullRequests(from payload: [String: Any]) -> [PullRequestItem] {
        var seen = Set<String>()
        var items: [PullRequestItem] = []

        // Alias order is our own (s0, s1, …); sort so results stay stable.
        for key in payload.keys.sorted(by: aliasOrder) {
            guard
                let search = payload[key] as? [String: Any],
                let nodes = search["nodes"] as? [[String: Any]]
            else { continue }

            for node in nodes {
                guard let item = pullRequest(from: node), seen.insert(item.id).inserted else { continue }
                items.append(item)
            }
        }

        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func aliasOrder(_ lhs: String, _ rhs: String) -> Bool {
        let left = Int(lhs.dropFirst()) ?? 0
        let right = Int(rhs.dropFirst()) ?? 0
        return left < right
    }

    static func pullRequest(from node: [String: Any]) -> PullRequestItem? {
        // An empty object appears for search hits that are not pull requests.
        guard
            let id = node["id"] as? String,
            let number = node["number"] as? Int,
            let title = node["title"] as? String,
            let urlString = node["url"] as? String,
            let url = URL(string: urlString)
        else { return nil }

        let repository = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? "?"
        let author = node["author"] as? [String: Any]
        let updatedAt = GitHubDate.date(from: node["updatedAt"] as? String)

        return PullRequestItem(
            id: id,
            number: number,
            title: title,
            repository: repository,
            // A deleted account leaves author null rather than omitting it.
            author: author?["login"] as? String ?? "ghost",
            authorAvatarURL: (author?["avatarUrl"] as? String).flatMap(URL.init(string:)),
            url: url,
            isDraft: node["isDraft"] as? Bool ?? false,
            updatedAt: updatedAt,
            reviewDecision: reviewDecision(node["reviewDecision"] as? String),
            checks: checks(from: node)
        )
    }

    static func reviewDecision(_ raw: String?) -> ReviewDecision {
        switch raw {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .reviewRequired
        default: .none
        }
    }

    static func checks(from node: [String: Any]) -> ChecksStatus {
        guard
            let commits = node["commits"] as? [String: Any],
            let nodes = commits["nodes"] as? [[String: Any]],
            let commit = nodes.first?["commit"] as? [String: Any],
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
