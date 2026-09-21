import Foundation

/// The signed-in user, resolved once per token.
public struct Viewer: Equatable, Sendable {
    public let login: String
    public let avatarURL: URL?
    public let scopes: TokenScopes
}

/// Result of a notifications poll.
public struct NotificationFetch: Sendable {
    /// Nil when GitHub answered 304 — nothing changed, keep what we have.
    public let items: [NotificationItem]?
    public let lastModified: String?
    /// GitHub's own minimum seconds between polls.
    public let pollInterval: TimeInterval?
}

public struct TeamMembership: Identifiable, Hashable, Sendable {
    /// "org/team" — the form GitHub's search qualifiers expect.
    public var id: String { slug }
    public let slug: String
    public let organisation: String
    public let name: String
}

/// Coordinates the API calls the app makes.
public struct GitHubService: Sendable {
    private let client: GitHubClient

    public init(token: String, session: URLSession = .shared) {
        client = GitHubClient(token: token, session: session)
    }

    /// Confirms the token works and reports who it belongs to and what it may
    /// do. The scope list comes from a response header, not the body, so it
    /// needs the raw response.
    public func viewer() async throws -> Viewer {
        let (data, response) = try await client.get(URL(string: "https://api.github.com/user")!)

        guard
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let login = object["login"] as? String
        else {
            throw GitHubError.decoding("could not read the user profile")
        }

        return Viewer(
            login: login,
            avatarURL: (object["avatar_url"] as? String).flatMap(URL.init(string:)),
            scopes: TokenScopes(header: response.value(forHTTPHeaderField: "X-OAuth-Scopes"))
        )
    }

    /// Teams the user belongs to, offered as a checklist in settings.
    public func teams() async throws -> [TeamMembership] {
        var url = URLComponents(string: "https://api.github.com/user/teams")!
        url.queryItems = [URLQueryItem(name: "per_page", value: "100")]

        let (data, _) = try await client.get(url.url!)
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw GitHubError.decoding("could not read team memberships")
        }

        return array.compactMap { entry in
            guard
                let slug = entry["slug"] as? String,
                let organisation = (entry["organization"] as? [String: Any])?["login"] as? String
            else { return nil }
            return TeamMembership(
                slug: "\(organisation)/\(slug)",
                organisation: organisation,
                name: entry["name"] as? String ?? slug
            )
        }
        .sorted { $0.slug < $1.slug }
    }

    /// Every open pull request in one repository, summarised per author.
    public func repositoryPullRequests(
        _ repository: String
    ) async throws -> [(item: PullRequestItem, reviewers: [ReviewerStatus])] {
        let payload = try await client.graphQL(PullRequestQuery.repositoryDocument(repository))
        return PullRequestParser.repositoryLoad(from: payload)
    }

    /// The extra detail behind one pull request, fetched when its row is
    /// opened rather than for the whole list.
    public func pullRequestDetail(id: String) async throws -> PullRequestDetail {
        let payload = try await client.graphQL(
            PullRequestDetailQuery.document,
            variables: ["id": id]
        )
        return try PullRequestDetailQuery.detail(from: payload)
    }

    /// Unread notification threads.
    ///
    /// GitHub asks clients to send back the previous `Last-Modified` value; a
    /// resulting 304 does not count against the rate limit, which matters at a
    /// one-minute poll interval. The response also carries `X-Poll-Interval`,
    /// the floor GitHub wants respected.
    public func notifications(since lastModified: String?) async throws -> NotificationFetch {
        var components = URLComponents(string: "https://api.github.com/notifications")!
        components.queryItems = [
            URLQueryItem(name: "all", value: "false"),
            URLQueryItem(name: "per_page", value: "50"),
        ]

        var headers: [String: String] = [:]
        if let lastModified {
            headers["If-Modified-Since"] = lastModified
        }

        let (data, response) = try await client.get(components.url!, headers: headers)
        let pollInterval = (response.value(forHTTPHeaderField: "X-Poll-Interval"))
            .flatMap(TimeInterval.init)

        guard response.statusCode != 304 else {
            return NotificationFetch(
                items: nil,
                lastModified: lastModified,
                pollInterval: pollInterval
            )
        }

        return NotificationFetch(
            items: try NotificationParser.notifications(from: data),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? lastModified,
            pollInterval: pollInterval
        )
    }

    /// The newest comment on a thread, fetched only when the user opens it.
    public func comment(at url: URL) async throws -> CommentPreview {
        let (data, _) = try await client.get(url)
        return NotificationParser.comment(from: data)
    }

    /// Marks one thread read. This changes state on GitHub, including in the
    /// web inbox, so it only ever runs on an explicit action.
    public func markRead(threadID: String) async throws {
        guard let url = URL(string: "https://api.github.com/notifications/threads/\(threadID)") else {
            throw GitHubError.decoding("invalid thread id")
        }
        try await client.patch(url)
    }

    /// Both pull request lists in one request: those waiting for the user's
    /// review, and those the user opened and is waiting on others for.
    public func pullRequests(
        login: String,
        teamSlugs: [String],
        repositoryFilters: [String]
    ) async throws -> (reviewRequested: [PullRequestItem], authored: [PullRequestItem]) {
        let payload = try await client.graphQL(
            PullRequestQuery.document(
                reviewRequested: PullRequestQuery.searchQueries(
                    login: login, teamSlugs: teamSlugs, repositoryFilters: repositoryFilters
                ),
                authored: [
                    PullRequestQuery.authoredQuery(
                        login: login, repositoryFilters: repositoryFilters
                    ),
                ]
            )
        )
        return (
            PullRequestParser.pullRequests(from: payload, group: .reviewRequested),
            PullRequestParser.pullRequests(from: payload, group: .authored)
        )
    }
}
