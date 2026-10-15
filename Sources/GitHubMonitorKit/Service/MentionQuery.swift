import Foundation

/// Reading who may be named with an `@` in a repository.
///
/// `mentionableUsers` is GitHub's own answer to this question -- the
/// people a mention will actually reach, which is not the same as the
/// people who have touched the repository, and not the same as its
/// members either. It takes a `query`, so a repository with four hundred
/// of them need not be held in memory to search.
public enum MentionQuery {
    /// How many to ask for at a time.
    ///
    /// Larger than the label picker's page because this list is filtered
    /// here rather than at GitHub for as long as it can be: a hundred
    /// logins is a small thing to hold and covers nearly every
    /// repository outright, which is what buys completion that appears
    /// as fast as somebody types.
    public static let pageSize = 100

    public static let document = """
    query($owner: String!, $name: String!, $query: String) {
      repository(owner: $owner, name: $name) {
        mentionableUsers(first: \(pageSize), query: $query) {
          totalCount
          nodes { login name avatarUrl }
        }
      }
    }
    """

    /// What the repository answered, and whether that was all of it.
    public struct Catalogue: Equatable, Sendable {
        public let users: [MentionableUser]
        public let total: Int

        public init(users: [MentionableUser], total: Int) {
            self.users = users
            self.total = total
        }

        /// Whether this page is the whole list. When it is, a name that
        /// is not in it is a name that cannot be mentioned, and there is
        /// nothing to be gained by asking GitHub again.
        public var isComplete: Bool { users.count >= total }
    }

    public static func catalogue(from payload: [String: Any]) throws -> Catalogue {
        guard
            let repository = payload["repository"] as? [String: Any],
            let container = repository["mentionableUsers"] as? [String: Any]
        else {
            throw GitHubError.decoding("repository has no mentionable users")
        }
        let nodes = container["nodes"] as? [[String: Any]] ?? []
        let users = nodes.compactMap { node -> MentionableUser? in
            guard let login = node["login"] as? String else { return nil }
            return MentionableUser(
                login: login,
                name: (node["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                avatarURL: (node["avatarUrl"] as? String).flatMap(URL.init(string:))
            )
        }
        return Catalogue(users: users, total: container["totalCount"] as? Int ?? users.count)
    }

    /// How many names to put under the editor at once.
    ///
    /// The list sits between what is being written and the buttons that
    /// send it. It is a suggestion, not a directory: past half a dozen
    /// it stops being quicker than typing the name.
    public static let shown = 6

    /// The people worth offering for what has been typed so far.
    ///
    /// Sorted by where the match falls rather than alphabetically. Typing
    /// "an" to reach "annika" should not have to scroll past "roman" and
    /// "susanne" first, and a login that begins with what was typed is
    /// nearly always the one meant.
    public static func matches(_ query: String, in users: [MentionableUser]) -> [MentionableUser] {
        guard !query.isEmpty else { return Array(users.prefix(shown)) }

        let wanted = query.lowercased()
        let scored = users.compactMap { user -> (MentionableUser, Int)? in
            let login = user.login.lowercased()
            let name = user.name?.lowercased() ?? ""
            if login.hasPrefix(wanted) { return (user, 0) }
            // A real name is how somebody is known to the person writing;
            // the login often is not. Worth matching, just not first.
            if name.hasPrefix(wanted) { return (user, 1) }
            if login.contains(wanted) { return (user, 2) }
            if name.contains(wanted) { return (user, 3) }
            return nil
        }

        return scored
            .sorted {
                $0.1 == $1.1
                    ? $0.0.login.localizedStandardCompare($1.0.login) == .orderedAscending
                    : $0.1 < $1.1
            }
            .prefix(shown)
            .map(\.0)
    }

    /// Whether GitHub is worth asking about this particular query.
    ///
    /// Only when the page already in hand is not the whole list and holds
    /// nothing matching. Otherwise the answer is already here, and asking
    /// again would put a request on every keystroke for a list that
    /// cannot have changed.
    public static func needsNarrowing(_ query: String, in catalogue: Catalogue) -> Bool {
        guard !query.isEmpty, !catalogue.isComplete else { return false }
        return matches(query, in: catalogue.users).isEmpty
    }
}
