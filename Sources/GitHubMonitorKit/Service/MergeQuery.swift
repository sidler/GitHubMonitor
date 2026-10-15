import Foundation

/// Merging a pull request, and everything that has to be true first.
///
/// The heaviest thing this app does. An approval can be dismissed and a
/// label can be clicked off; a merge puts somebody's code in a branch
/// other people build from, and the way back is a revert with its own
/// history. So it is built like the approval and then some: the state of
/// the pull request is read again immediately before the question is
/// asked, the commit that was read is the commit that is merged, and
/// anything the app already knows to be in the way stops the button
/// before a request is made at all.
public enum MergeQuery {
    /// The three ways GitHub will do it, and what a repository calls
    /// each one.
    public enum Method: String, Hashable, Sendable, CaseIterable {
        case merge = "MERGE"
        case squash = "SQUASH"
        case rebase = "REBASE"

        public var label: String {
            switch self {
            case .merge: "Create a merge commit"
            case .squash: "Squash and merge"
            case .rebase: "Rebase and merge"
            }
        }

        /// What the button says when this is the only one allowed.
        public var action: String {
            switch self {
            case .merge: "Merge"
            case .squash: "Squash and merge"
            case .rebase: "Rebase and merge"
            }
        }
    }

    /// What GitHub says about the pull request right now, asked again
    /// immediately before the question goes up.
    public struct Readiness: Equatable, Sendable {
        public let commit: String
        public let isMerged: Bool
        public let isClosed: Bool
        public let mergeStatus: MergeStatus
        /// What the repository permits, in the order GitHub lists them.
        public let methods: [Method]

        public init(
            commit: String,
            isMerged: Bool,
            isClosed: Bool,
            mergeStatus: MergeStatus,
            methods: [Method]
        ) {
            self.commit = commit
            self.isMerged = isMerged
            self.isClosed = isClosed
            self.mergeStatus = mergeStatus
            self.methods = methods
        }
    }

    public static let readinessDocument = """
    query($id: ID!) {
      node(id: $id) {
        ... on PullRequest {
          headRefOid
          merged
          closed
          mergeable
          # A repository's own rule about how its history is kept. Asked
          # with the rest rather than remembered: it is a setting
          # somebody can change, and the cost of being wrong about it is
          # a button that does something the team decided against.
          repository {
            mergeCommitAllowed
            squashMergeAllowed
            rebaseMergeAllowed
          }
        }
      }
    }
    """

    public static func readiness(from payload: [String: Any]) throws -> Readiness {
        guard
            let node = payload["node"] as? [String: Any],
            let commit = node["headRefOid"] as? String
        else {
            throw GitHubError.decoding("pull request not found")
        }

        let repository = node["repository"] as? [String: Any] ?? [:]
        var methods: [Method] = []
        if repository["mergeCommitAllowed"] as? Bool == true { methods.append(.merge) }
        if repository["squashMergeAllowed"] as? Bool == true { methods.append(.squash) }
        if repository["rebaseMergeAllowed"] as? Bool == true { methods.append(.rebase) }

        return Readiness(
            commit: commit,
            isMerged: node["merged"] as? Bool ?? false,
            isClosed: node["closed"] as? Bool ?? false,
            mergeStatus: PullRequestParser.mergeStatus(node["mergeable"] as? String),
            methods: methods
        )
    }

    /// What the app already knows to be in the way, before anything is
    /// asked of GitHub.
    ///
    /// These three are the ones that were chosen: a conflict, checks that
    /// are not green, and a review that was required and is not there.
    /// GitHub refuses most of them itself
    /// on a protected branch, but a button that offers something and then
    /// reports a refusal is a button that wasted somebody's nerve -- and
    /// on an unprotected branch it would not refuse at all, which is
    /// worse.
    public static func blocker(for item: PullRequestItem) -> String? {
        if item.state != .open { return "This pull request is not open." }
        if item.isDraft { return "This pull request is still a draft." }
        if item.mergeStatus == .conflicting { return "It conflicts with its base branch." }
        switch item.checks {
        case .failure: return "Its checks have not passed."
        case .pending: return "Its checks are still running."
        case .success, .none: break
        }
        // Not "anything that is not an approval". A pull request in a
        // repository that requires no review comes back with no decision
        // at all, and GitHub merges it happily -- refusing that here made
        // the button permanently grey everywhere branch protection is not
        // switched on, which is most places. What is in the way is a
        // review that was asked for and is missing, or one that asked for
        // changes; having been nobody's business to review is not.
        switch item.reviewDecision {
        case .changesRequested: return "Somebody has asked for changes."
        case .reviewRequired: return "It still needs an approving review."
        case .approved, .none: break
        }
        return nil
    }

    /// What the fresh answer adds: things that can only be known by
    /// asking, and that may have become true since the last refresh.
    public static func refusal(comparing readiness: Readiness, against commit: String?) -> String? {
        if readiness.isMerged { return "It has already been merged." }
        if readiness.isClosed { return "It has been closed." }
        if readiness.mergeStatus == .conflicting {
            return "It conflicts with its base branch."
        }
        if let commit, commit != readiness.commit {
            // The same guard the approval has, for the same reason: what
            // was read is what is acted on, and a push between the two is
            // exactly the moment this matters.
            return "Somebody pushed to it since this was read. Refresh and look again."
        }
        if readiness.methods.isEmpty {
            return "This repository allows no merge method the app can use."
        }
        return nil
    }

    public static let mergeDocument = """
    mutation($id: ID!, $commit: GitObjectID!, $method: PullRequestMergeMethod!) {
      mergePullRequest(input: {
        pullRequestId: $id,
        expectedHeadOid: $commit,
        mergeMethod: $method
      }) {
        clientMutationId
      }
    }
    """
}
