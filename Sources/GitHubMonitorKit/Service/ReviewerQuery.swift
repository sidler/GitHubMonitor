import Foundation

/// Somebody who could be asked to review, as the picker needs them.
public struct ReviewerCandidate: Identifiable, Hashable, Sendable {
    /// The GraphQL node id, which is what the request is made with.
    public let id: String
    public let login: String
    /// Their real name where GitHub has one. Shown beside the login
    /// because a repository of twenty-seven people is a list of logins
    /// nobody can read.
    public let name: String?
    public let avatarURL: URL?

    public init(id: String, login: String, name: String?, avatarURL: URL?) {
        self.id = id
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// Which repository's people are being asked for, and under what filter.
public struct ReviewerListing: Hashable, Sendable {
    public let repository: String
    /// Empty for the opening list; GitHub's own search once two letters
    /// have been typed.
    public let query: String

    public init(repository: String, query: String) {
        self.repository = repository
        self.query = query
    }
}

/// Who may be asked to review, and the asking itself.
public enum ReviewerQuery {
    /// Fifty at a time, filtered by GitHub rather than here: a repository
    /// with hundreds of collaborators would otherwise show the first
    /// fifty alphabetically and look as though the rest had left.
    public static let pageSize = 50

    public struct Catalogue: Equatable, Sendable {
        public let candidates: [ReviewerCandidate]
        public let total: Int

        public var isComplete: Bool { candidates.count >= total }

        public init(candidates: [ReviewerCandidate], total: Int) {
            self.candidates = candidates
            self.total = total
        }
    }

    public static let document = """
    query($owner: String!, $name: String!, $query: String, $first: Int!) {
      rateLimit { remaining cost }
      repository(owner: $owner, name: $name) {
        collaborators(first: $first, query: $query) {
          totalCount
          nodes { id login name avatarUrl }
        }
      }
    }
    """

    public static func variables(for listing: ReviewerListing) -> [String: Any]? {
        guard let parts = ChangedFilesQuery.repository(listing.repository) else { return nil }
        var variables: [String: Any] = [
            "owner": parts.owner, "name": parts.name, "first": pageSize,
        ]
        // Null rather than an empty string: an empty filter matches
        // nobody, where no filter at all means everybody.
        if !listing.query.isEmpty { variables["query"] = listing.query }
        return variables
    }

    public static func catalogue(from payload: [String: Any]) throws -> Catalogue {
        guard
            let repository = payload["repository"] as? [String: Any],
            let people = repository["collaborators"] as? [String: Any]
        else {
            throw GitHubError.decoding("the repository's people were not in the answer")
        }
        let nodes = people["nodes"] as? [[String: Any]] ?? []
        return Catalogue(
            candidates: nodes.compactMap(candidate(from:)),
            total: people["totalCount"] as? Int ?? nodes.count
        )
    }

    static func candidate(from node: [String: Any]) -> ReviewerCandidate? {
        guard
            let id = node["id"] as? String,
            let login = node["login"] as? String
        else { return nil }
        let name = (node["name"] as? String)?.trimmingCharacters(in: .whitespaces)
        return ReviewerCandidate(
            id: id,
            login: login,
            name: (name?.isEmpty ?? true) ? nil : name,
            avatarURL: (node["avatarUrl"] as? String).flatMap(URL.init(string:))
        )
    }

    /// The people worth offering, in the order worth offering them.
    ///
    /// Anybody already asked is dropped rather than ticked: this picker
    /// adds, and a row that looks like a checkbox and cannot be unticked
    /// is a worse answer than no row. The reviewers already on the pull
    /// request are listed above it anyway.
    ///
    /// The author goes too. GitHub refuses a review request from somebody
    /// on their own pull request, and an entry that always fails is not an
    /// entry.
    public static func offerable(
        _ candidates: [ReviewerCandidate],
        asked: Set<String>,
        author: String?,
        viewer: String?
    ) -> [ReviewerCandidate] {
        let out = Set(
            ([author, viewer].compactMap { $0 }).map { $0.lowercased() }
        )
        return candidates.filter {
            !asked.contains($0.login.lowercased()) && !out.contains($0.login.lowercased())
        }
    }

    /// Asking, as an addition rather than a replacement.
    ///
    /// `union: true` is the whole of why this is safe. Without it
    /// `requestReviews` sets the reviewer list to exactly what it is
    /// given -- so adding one person by naming one person would withdraw
    /// the request from everybody else, silently, and the only sign would
    /// be colleagues wondering why their review had disappeared.
    public static let requestDocument = """
    mutation($id: ID!, $users: [ID!]!) {
      requestReviews(input: { pullRequestId: $id, userIds: $users, union: true }) {
        pullRequest { id }
      }
    }
    """

    /// Taking it back, by name and nobody else's.
    ///
    /// REST rather than GraphQL, which has no mutation for withdrawing
    /// one request: there, taking somebody off means calling
    /// `requestReviews` again with `union: false` and the whole list of
    /// everyone who should remain -- which needs node ids the pane does
    /// not have, and stamps on anyone added meanwhile. This endpoint
    /// takes logins and removes exactly those.
    public static func withdrawalURL(repository: String, number: Int) -> URL? {
        guard let parts = ChangedFilesQuery.repository(repository) else { return nil }
        return URL(
            string: "https://api.github.com/repos/\(parts.owner)/\(parts.name)"
                + "/pulls/\(number)/requested_reviewers"
        )
    }

    /// How long the way back stays on offer.
    ///
    /// Long enough to notice the wrong name and undo it, short enough
    /// that it is gone before anybody treats it as a second step of the
    /// asking. The request itself goes out immediately either way -- this
    /// is a way back, not a pause for thought.
    public static let undoWindow: TimeInterval = 12
}

/// A review request just made, for as long as it can still be taken back.
public struct ReviewRequestUndo: Equatable, Sendable {
    public let pullRequestID: String
    public let repository: String
    public let number: Int
    public let login: String
    public var isWorking = false
    public var failure: String?

    public init(
        pullRequestID: String,
        repository: String,
        number: Int,
        login: String,
        isWorking: Bool = false,
        failure: String? = nil
    ) {
        self.pullRequestID = pullRequestID
        self.repository = repository
        self.number = number
        self.login = login
        self.isWorking = isWorking
        self.failure = failure
    }
}

/// What the pane has to draw while the people are on their way.
public enum ReviewerCatalogueState: Equatable, Sendable {
    case loading
    case loaded(ReviewerQuery.Catalogue)
    case failed(String)
}
