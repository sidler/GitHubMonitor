import Foundation

/// Turns the GraphQL payload into model objects.
///
/// Kept separate from the client so it can be tested against recorded
/// responses without a network.
public enum PullRequestParser {
    /// Pull requests paired with their reviewers, for the dashboard.
    ///
    /// Reuses the detail parser's reviewer logic, which already merges
    /// outstanding requests with reviews already left.
    public static func repositoryLoad(from payload: [String: Any]) -> [(item: PullRequestItem, reviewers: [ReviewerStatus])] {
        guard
            let search = payload["d0"] as? [String: Any],
            let nodes = search["nodes"] as? [[String: Any]]
        else { return [] }

        return nodes.compactMap { node in
            guard let item = pullRequest(from: node) else { return nil }
            return (item, PullRequestDetailQuery.reviewers(from: node))
        }
    }

    static func pullRequest(
        from node: [String: Any], requestedOf viewer: String? = nil
    ) -> PullRequestItem? {
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
            createdAt: GitHubDate.date(from: node["createdAt"] as? String),
            updatedAt: updatedAt,
            reviewDecision: reviewDecision(node["reviewDecision"] as? String),
            checks: checks(from: node),
            mergeStatus: mergeStatus(node["mergeable"] as? String),
            headCommit: node["headRefOid"] as? String,
            viewerDidAuthor: node["viewerDidAuthor"] as? Bool ?? false,
            viewerReview: viewerReview(from: node),
            isAutoMergeArmed: (node["autoMergeRequest"] as? [String: Any]) != nil,
            reviewRequestedAt: reviewRequested(from: node, of: viewer),
            reviews: reviewTally(from: node)
        )
    }

    /// Counts the reviewers behind a pull request.
    ///
    /// The lists ask for `latestOpinionatedReviews`, the dashboard for
    /// `latestReviews` because it needs the reviewers' names as well. Both
    /// carry one entry per reviewer, and only an approval or a request for
    /// changes is counted either way, so the same reading serves both.
    static func reviewTally(from node: [String: Any]) -> ReviewTally {
        let reviews = (node["latestOpinionatedReviews"] ?? node["latestReviews"]) as? [String: Any]
        let states = (reviews?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["state"] as? String }

        return ReviewTally(
            accepted: states.count { $0 == "APPROVED" },
            declined: states.count { $0 == "CHANGES_REQUESTED" },
            pending: (node["reviewRequests"] as? [String: Any])?["totalCount"] as? Int ?? 0
        )
    }

    /// When this person was first asked to review.
    ///
    /// Only events that name them. A request made of a team names the team,
    /// and treating that as a request of everyone in it would put a clock on
    /// pull requests nobody was personally asked about -- the earliest
    /// reading would then be the team's, not theirs.
    ///
    /// The earliest such event rather than the latest: the question is how
    /// long this has been sitting, and a second request does not restart it.
    static func reviewRequested(from node: [String: Any], of viewer: String?) -> Date? {
        guard let viewer, !viewer.isEmpty else { return nil }
        guard
            let timeline = node["timelineItems"] as? [String: Any],
            let nodes = timeline["nodes"] as? [[String: Any]]
        else { return nil }

        return nodes.compactMap { event -> Date? in
            let reviewer = event["requestedReviewer"] as? [String: Any]
            guard (reviewer?["login"] as? String)?.caseInsensitiveCompare(viewer) == .orderedSame,
                  let raw = event["createdAt"] as? String
            else { return nil }
            return GitHubDate.date(from: raw)
        }
        .min()
    }

    /// Absent where they have not reviewed it, which is the ordinary case
    /// for something still waiting on them.
    static func viewerReview(from node: [String: Any]) -> ViewerReview? {
        guard
            let review = node["viewerLatestReview"] as? [String: Any],
            let raw = review["state"] as? String
        else { return nil }
        return ViewerReview(
            state: ReviewState(apiValue: raw),
            submittedAt: GitHubDate.optional(from: review["submittedAt"] as? String)
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

    /// Anything but the two answers -- including the field being absent,
    /// which is how the dashboard's own query comes back -- is unknown.
    static func mergeStatus(_ raw: String?) -> MergeStatus {
        switch raw {
        case "MERGEABLE": .mergeable
        case "CONFLICTING": .conflicting
        default: .unknown
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
