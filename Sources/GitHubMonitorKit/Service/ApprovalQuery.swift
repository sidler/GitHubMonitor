import Foundation

/// Approving a pull request, and the check that has to come first.
///
/// The only thing this app writes that other people see. Everything about it
/// is built around one fact: an approval is public, it cannot be taken back,
/// and where auto-merge is armed it can put code into the main branch -- so
/// it is never sent against anything but the commit whose diff was on screen.
public enum ApprovalQuery {
    /// The head commit as it is right now.
    ///
    /// Asked immediately before approving rather than read from the last
    /// refresh: the gap this closes is the five minutes since that refresh,
    /// which is exactly when the push that matters arrives.
    public static let headDocument = """
    query($id: ID!) {
      node(id: $id) {
        ... on PullRequest {
          headRefOid
          merged
          closed
        }
      }
    }
    """

    public static func head(from payload: [String: Any]) throws -> HeadState {
        guard
            let node = payload["node"] as? [String: Any],
            let oid = node["headRefOid"] as? String
        else {
            throw GitHubError.decoding("pull request not found")
        }
        return HeadState(
            commit: oid,
            isMerged: node["merged"] as? Bool ?? false,
            isClosed: node["closed"] as? Bool ?? false
        )
    }

    public struct HeadState: Equatable, Sendable {
        public let commit: String
        public let isMerged: Bool
        public let isClosed: Bool

        public init(commit: String, isMerged: Bool, isClosed: Bool) {
            self.commit = commit
            self.isMerged = isMerged
            self.isClosed = isClosed
        }
    }

    /// `commitOID` is what binds the approval to what was read. Without it
    /// GitHub attaches the review to whatever the head happens to be when
    /// the request lands.
    /// What a review says about the whole, beside whatever it says about
    /// the lines.
    public enum Event: String, Sendable, CaseIterable {
        case approve = "APPROVE"
        case comment = "COMMENT"
        case requestChanges = "REQUEST_CHANGES"

        /// What the button says, where there is nothing else to mention.
        public var verb: String {
            switch self {
            case .approve: "Approve"
            case .comment: "Comment"
            case .requestChanges: "Request changes"
            }
        }

        /// Whether it is worth sending with nothing attached. An approval
        /// is; a review that neither approves nor objects and says
        /// nothing is an empty envelope, and GitHub refuses it.
        public var standsAlone: Bool { self == .approve }
    }

    /// One review, said in one request.
    ///
    /// The remarks travel with it as `threads` rather than being attached
    /// one at a time to a pending review. That is the field GitHub now
    /// points at -- the older `comments` is on its way out -- and it
    /// means a review is one call that either happens or does not,
    /// instead of a pending review that can be left half built if
    /// something fails in the middle.
    public static let submitDocument = """
    mutation(
      $id: ID!,
      $commit: GitObjectID!,
      $event: PullRequestReviewEvent!,
      $threads: [DraftPullRequestReviewThread!]
    ) {
      addPullRequestReview(input: {
        pullRequestId: $id,
        commitOID: $commit,
        event: $event,
        threads: $threads
      }) {
        pullRequestReview { state }
      }
    }
    """

    /// The remarks, in the shape the mutation wants them.
    ///
    /// `side` is which file the line belongs to: the new one for nearly
    /// everything, the old one for a remark on a line that was removed.
    public static func threads(from comments: [DraftComment]) -> [[String: Any]] {
        comments.map { comment in
            [
                "path": comment.path,
                "line": comment.line,
                "side": comment.side == .old ? "LEFT" : "RIGHT",
                "body": comment.body,
            ]
        }
    }

    /// What stops an approval before it is sent.
    public enum Refusal: LocalizedError, Equatable {
        /// Someone pushed since the diff was read.
        case moved(from: String, to: String)
        case merged
        case closed

        public var errorDescription: String? {
            switch self {
            case .moved(let from, let to):
                "A commit was pushed since this diff was read "
                    + "(\(Self.short(from)) → \(Self.short(to))). Nothing was approved."
            case .merged:
                "This pull request has already been merged."
            case .closed:
                "This pull request has been closed."
            }
        }

        static func short(_ commit: String) -> String { String(commit.prefix(7)) }
    }

    /// Whether the pull request is still the one that was read.
    public static func refusal(
        comparing head: HeadState, against shown: String?
    ) -> Refusal? {
        if head.isMerged { return .merged }
        if head.isClosed { return .closed }
        // No commit to compare against means the row predates this feature
        // or came from a query that does not ask for it; refusing then would
        // block approving for a reason nobody can act on.
        guard let shown, shown != head.commit else { return nil }
        return .moved(from: shown, to: head.commit)
    }

    /// What the confirmation says.
    ///
    /// Two facts, in the order they matter: the approval is public and
    /// final, and -- where a merge is already armed and waiting on one more
    /// yes -- that pressing this may put the change into the base branch.
    /// The second sentence is the reason this dialog exists at all.
    public static func confirmation(
        repository: String,
        number: Int,
        isAutoMergeArmed: Bool,
        event: Event = .approve,
        remarks: Int = 0
    ) -> String {
        var base = "\(repository) #\(number). "
        if remarks > 0 {
            base += remarks == 1
                ? "One remark goes with it. "
                : "\(remarks) remarks go with it. "
        }
        switch event {
        case .approve:
            base += "An approval is visible to everyone and cannot be taken back."
        case .comment:
            base += "It is visible to everyone and cannot be taken back."
        case .requestChanges:
            base += "Asking for changes is visible to everyone and cannot be taken back."
        }
        guard isAutoMergeArmed, event == .approve else { return base }
        return base + "\n\nAuto-merge is armed on this pull request: "
            + "if yours is the last approval it needs, it will be merged."
    }
}
