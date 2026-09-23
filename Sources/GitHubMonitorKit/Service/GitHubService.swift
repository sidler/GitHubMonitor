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

    /// The description and the end of the conversation behind a
    /// notification, for the pane that shows it.
    public func thread(at subjectURL: URL) async throws -> IssueDetail {
        guard let subject = ThreadQuery.subject(from: subjectURL) else {
            throw GitHubError.decoding("not a conversation this app can read")
        }
        let payload = try await client.graphQL(
            ThreadQuery.document,
            variables: [
                "owner": subject.owner,
                "name": subject.name,
                "number": subject.number,
            ]
        )
        return try ThreadQuery.thread(from: payload)
    }

    /// The newest comment on a thread, fetched only when the user opens it.
    public func comment(at url: URL) async throws -> CommentPreview {
        let (data, _) = try await client.get(url)
        return NotificationParser.comment(from: data)
    }

    // MARK: - Trends

    /// Every merged pull request of one period, with the timestamps the
    /// trend charts measure.
    ///
    /// Paged to the end rather than sampled: a median of the first hundred
    /// would be a median of the first hundred, not of the period. The quota
    /// left is reported back so the caller can stop before it runs out.
    public func mergedTimings(
        repository: String,
        period: DateInterval
    ) async throws -> (timings: [PullRequestTiming], remainingQuota: Int?) {
        try await mergedTimings(
            matching: TrendQuery.mergedQuery(repository: repository, period: period)
        )
    }

    /// The same, for any search: the personal charts ask for one author's
    /// merges rather than a repository's.
    public func mergedTimings(
        matching query: String
    ) async throws -> (timings: [PullRequestTiming], remainingQuota: Int?) {
        var timings: [PullRequestTiming] = []
        var cursor: String?
        var remaining: Int?

        repeat {
            let payload = try await client.graphQL(
                TrendQuery.mergedDocument,
                variables: [
                    "query": query,
                    "cursor": cursor as Any,
                ]
            )
            let page = TrendQuery.mergedPage(from: payload)
            timings += page.items
            remaining = page.remainingQuota
            cursor = page.cursor
        } while cursor != nil

        return (timings, remaining)
    }

    /// How many pull requests were opened in one period, and how many of
    /// those a person opened.
    public func openedCounts(
        repository: String,
        period: DateInterval
    ) async throws -> (byPeople: Int, byEveryone: Int, remainingQuota: Int?) {
        var total = 0
        var bots = 0
        var cursor: String?
        var remaining: Int?

        repeat {
            let payload = try await client.graphQL(
                TrendQuery.openedDocument,
                variables: [
                    "query": TrendQuery.openedQuery(repository: repository, period: period),
                    "cursor": cursor as Any,
                ]
            )
            let page = TrendQuery.openedPage(from: payload)
            total += page.items.count
            bots += page.items.count { $0 }
            remaining = page.remainingQuota
            cursor = page.cursor
        } while cursor != nil

        return (total - bots, total, remaining)
    }

    /// One person's pull requests from one period, with what was said on
    /// them.
    public func myPullRequests(
        matching query: String
    ) async throws -> (facts: [MyPullRequestFacts], remainingQuota: Int?) {
        var facts: [MyPullRequestFacts] = []
        var cursor: String?
        var remaining: Int?

        repeat {
            let payload = try await client.graphQL(
                MyTrendQuery.document,
                variables: ["query": query, "cursor": cursor as Any]
            )
            let page = MyTrendQuery.page(from: payload)
            facts += page.items
            remaining = page.remainingQuota
            cursor = page.cursor
        } while cursor != nil

        return (facts, remaining)
    }

    /// Marks one thread read. This changes state on GitHub, including in the
    /// web inbox, so it only ever runs on an explicit action.
    public func markRead(threadID: String) async throws {
        guard let url = URL(string: "https://api.github.com/notifications/threads/\(threadID)") else {
            throw GitHubError.decoding("invalid thread id")
        }
        try await client.patch(url)
    }

    /// Every list in one request: whatever searches the saved lists come to,
    /// each under its own alias.
    public func lists(_ searches: [ListSearch]) async throws -> ListResults {
        guard !searches.isEmpty else { return ListResults() }
        let payload = try await client.graphQL(ListQuery.document(searches))
        return ListParser.results(from: payload, searches: searches)
    }

    /// The text and the end of the thread behind one issue, fetched when its
    /// row is opened rather than for the whole list.
    public func issueDetail(id: String) async throws -> IssueDetail {
        let payload = try await client.graphQL(
            IssueQuery.detailDocument,
            variables: ["id": id]
        )
        return try IssueQuery.detail(from: payload)
    }
}
