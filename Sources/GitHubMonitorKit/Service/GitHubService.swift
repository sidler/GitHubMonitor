import Foundation

/// The signed-in user, resolved once per token.
public struct Viewer: Equatable, Sendable {
    public let login: String
    public let avatarURL: URL?
    public let scopes: TokenScopes
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

    public func pullRequests(
        login: String,
        teamSlugs: [String],
        repositoryFilters: [String]
    ) async throws -> [PullRequestItem] {
        let queries = PullRequestQuery.searchQueries(
            login: login, teamSlugs: teamSlugs, repositoryFilters: repositoryFilters
        )
        let payload = try await client.graphQL(PullRequestQuery.document(for: queries))
        return PullRequestParser.pullRequests(from: payload)
    }
}
