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
    /// What is left of the REST allowance, which this request reports on
    /// every call including a 304.
    public let budget: RateBudget?
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
    /// Every open pull request in one repository, paged.
    ///
    /// The chart adds these up, so a page that never arrives is not a row
    /// nobody scrolled to -- it is a bar that is too short. Measured on the
    /// repository this was written for: 210 open, where one page is 100.
    public func repositoryPullRequests(
        _ repository: String
    ) async throws -> (
        entries: [(item: PullRequestItem, reviewers: [ReviewerStatus])],
        unread: Int,
        budget: RateBudget?
    ) {
        var entries: [(item: PullRequestItem, reviewers: [ReviewerStatus])] = []
        var cursor: String?
        var total = 0
        var budget: RateBudget?
        // Charged per page, and the chart's cost is all of them together.
        var spent = 0
        var stoppedEarly = false
        // A page that reports another page while yielding nothing parsable
        // would otherwise keep this going for ever: the row cap never trips
        // if no rows arrive.
        var pagesLeft = PullRequestQuery.dashboardLimit / PullRequestQuery.pageSize + 1

        repeat {
            pagesLeft -= 1
            let payload = try await client.graphQL(
                PullRequestQuery.repositoryDocument(repository, cursor: cursor)
            )
            let page = PullRequestParser.repositoryPage(from: payload)
            entries += page.entries
            if total == 0 { total = page.total }
            if let reading = ListParser.budget(from: payload) {
                spent += reading.cost
                budget = reading
            }

            if entries.count >= PullRequestQuery.dashboardLimit || pagesLeft <= 0 {
                stoppedEarly = page.cursor != nil
                cursor = nil
            } else {
                cursor = page.cursor
            }
        } while cursor != nil

        return (
            entries,
            PullRequestQuery.unread(
                total: total, read: entries.count, stoppedEarly: stoppedEarly
            ),
            budget?.costing(spent)
        )
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
        // The REST allowance is its own, and this is the request that spends
        // most of it -- it runs on every refresh, conditional or not.
        let budget = GitHubClient.budget(from: response)

        guard response.statusCode != 304 else {
            return NotificationFetch(
                items: nil,
                lastModified: lastModified,
                pollInterval: pollInterval,
                budget: budget
            )
        }

        return NotificationFetch(
            items: try NotificationParser.notifications(from: data),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? lastModified,
            pollInterval: pollInterval,
            budget: budget
        )
    }

    /// The description and the end of the conversation behind a
    /// notification, for the pane that shows it.
    /// Where the pull request's head is right now.
    public func head(of pullRequestID: String) async throws -> ApprovalQuery.HeadState {
        let payload = try await client.graphQL(
            ApprovalQuery.headDocument, variables: ["id": pullRequestID]
        )
        return try ApprovalQuery.head(from: payload)
    }

    /// Which files of a pull request this person has already ticked off.
    ///
    /// Paged to the same ceiling the patches stop at, so the answer covers
    /// what the overlay can show and no more.
    public func viewedFiles(
        pullRequestID: String
    ) async throws -> (states: [String: FileViewedState], budget: RateBudget?) {
        var states: [String: FileViewedState] = [:]
        var budget: RateBudget?
        var spent = 0
        var cursor: String?
        // A page that reports another page while yielding nothing would
        // otherwise keep this going: the file cap counts files, not rounds.
        var pagesLeft = ViewedFilesQuery.maximumFiles / ViewedFilesQuery.pageSize + 1

        repeat {
            pagesLeft -= 1
            var variables: [String: Any] = ["id": pullRequestID]
            if let cursor { variables["after"] = cursor }
            let payload = try await client.graphQL(ViewedFilesQuery.document, variables: variables)
            let page = ViewedFilesQuery.page(from: payload)
            states.merge(page.states) { _, new in new }
            if let reading = ListParser.budget(from: payload) {
                spent += reading.cost
                budget = reading
            }
            cursor = (states.count >= ViewedFilesQuery.maximumFiles || pagesLeft <= 0)
                ? nil
                : page.cursor
        } while cursor != nil

        return (states, budget?.costing(spent))
    }

    /// The conversations hanging off a pull request's diff.
    ///
    /// Fetched when the diff is opened rather than with the file list: the
    /// query carries every comment body, which is not something to pay for
    /// each time somebody arrows down the list of pull requests.
    public func reviewThreads(
        pullRequestID: String
    ) async throws -> (threads: [ReviewThread], budget: RateBudget?) {
        var threads: [ReviewThread] = []
        var budget: RateBudget?
        var spent = 0
        var cursor: String?
        // A page that reports another page while yielding nothing would
        // otherwise keep this going: the cap counts threads, not rounds.
        var pagesLeft = ReviewThreadsQuery.maximumThreads / ReviewThreadsQuery.pageSize + 1

        repeat {
            pagesLeft -= 1
            var variables: [String: Any] = ["id": pullRequestID]
            if let cursor { variables["after"] = cursor }
            let payload = try await client.graphQL(
                ReviewThreadsQuery.document, variables: variables
            )
            let page = ReviewThreadsQuery.page(from: payload)
            threads += page.threads
            if let reading = ListParser.budget(from: payload) {
                spent += reading.cost
                budget = reading
            }
            cursor = (threads.count >= ReviewThreadsQuery.maximumThreads || pagesLeft <= 0)
                ? nil
                : page.cursor
        } while cursor != nil

        return (threads, budget?.costing(spent))
    }

    /// Ticks one file off, or takes the tick back.
    public func setViewed(
        _ viewed: Bool, pullRequestID: String, path: String
    ) async throws {
        _ = try await client.graphQL(
            ViewedFilesQuery.document(setting: viewed),
            variables: ["id": pullRequestID, "path": path]
        )
    }

    /// Looks up linked issues and pull requests by number.
    ///
    /// One request for the lot: this costs a point whatever it carries
    /// back, exactly as a search does, so asking for eight links one at a
    /// time would cost eight times what asking together does.
    public func linkedItems(
        _ references: [ItemReference]
    ) async throws -> (summaries: [ItemReference: LinkedSummaryState], budget: RateBudget?) {
        guard let document = LinkedItemQuery.document(for: references) else { return ([:], nil) }
        let payload = try await client.graphQL(document)
        return (
            LinkedItemQuery.summaries(from: payload, asked: references),
            ListParser.budget(from: payload)
        )
    }

    /// Approves a pull request, bound to one commit.
    public func approve(pullRequestID: String, commit: String) async throws {
        _ = try await client.graphQL(
            ApprovalQuery.approveDocument,
            variables: ["id": pullRequestID, "commit": commit]
        )
    }

    /// The files one pull request touches, with their patches.
    ///
    /// Paged: asking for one page of a hundred and stopping meant a pull
    /// request touching three hundred files showed a hundred of them, with
    /// the count above the list saying three hundred.
    public func changedFiles(repository: String, number: Int) async throws -> [ChangedFile] {
        guard let parts = ChangedFilesQuery.repository(repository) else {
            throw GitHubError.decoding("not a repository this app can read")
        }

        var files: [ChangedFile] = []
        var page = 1
        while files.count < ChangedFilesQuery.maximumFiles {
            guard let url = ChangedFilesQuery.url(
                owner: parts.owner, name: parts.name, number: number, page: page
            ) else {
                throw GitHubError.decoding("not a repository this app can read")
            }
            let (data, _) = try await client.get(url)
            let read = try ChangedFilesQuery.files(from: data)
            files += read
            // A short page is the last one. REST says so by giving back
            // fewer than asked for, which is also what stops this where a
            // page repeats itself or comes back empty.
            guard read.count == ChangedFilesQuery.pageSize else { break }
            page += 1
        }

        return ChangedFilesQuery.ordered(files)
    }

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

    /// How long one person took over the reviews they were asked for.
    public func reviewResponses(
        matching query: String, viewer: String
    ) async throws -> (responses: [ReviewResponse], remainingQuota: Int?) {
        var responses: [ReviewResponse] = []
        var cursor: String?
        var remaining: Int?

        repeat {
            let payload = try await client.graphQL(
                MyTrendQuery.responseDocument,
                variables: [
                    "query": query,
                    "cursor": cursor as Any,
                    "login": viewer,
                ]
            )
            let page = MyTrendQuery.responsePage(from: payload, viewer: viewer)
            responses += page.items
            remaining = page.remainingQuota
            cursor = page.cursor
        } while cursor != nil

        return (responses, remaining)
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
    /// Every list's rows, paged until GitHub runs out or the cap is reached.
    ///
    /// The first request covers all the searches at once; only the ones with
    /// more to give are asked again, together, so a queue of a hundred and
    /// nine costs two requests rather than two per list.
    public func lists(
        _ searches: [ListSearch], viewer: String? = nil
    ) async throws -> (
        results: ListResults,
        unread: [String: Int],
        budget: RateBudget?,
        failures: [String: String]
    ) {
        guard !searches.isEmpty else { return (ListResults(), [:], nil, [:]) }

        var results = ListResults()
        var budget: RateBudget?
        // Every round is charged separately, and the sentence in settings
        // is about what one refresh costs, not one request of it.
        var spent = 0
        /// Lists GitHub refused, kept out of the way of the ones it did not.
        var failures: [String: String] = [:]
        var round: [(search: ListSearch, cursor: String?)] = searches.map { ($0, nil) }
        var isFirstRound = true
        /// Lists that still had pages when the cap stopped them, which is
        /// the only case where anything can honestly be called missing.
        var stoppedAtCap: Set<String> = []
        // A page that reports another page while yielding no new rows would
        // otherwise keep this going; the cap counts rows, not requests.
        var roundsLeft = ListQuery.maximumItems / ListQuery.pageSize + 1

        while !round.isEmpty, roundsLeft > 0 {
            roundsLeft -= 1
            let batch = round.map(\.search)
            var cursors: [Int: String] = [:]
            for (position, entry) in round.enumerated() where entry.cursor != nil {
                cursors[position] = entry.cursor
            }

            // The answer rather than only the data: one list written with
            // a qualifier GitHub will not take should not stop the others
            // from refreshing.
            let answer = try await client.graphQLAnswer(
                ListQuery.document(batch, cursors: cursors)
            )
            let payload = answer.data
            failures.merge(ListParser.failures(answer.failures, searches: batch)) { held, _ in held }
            // A complaint that names no list is about the request itself,
            // and there is nothing partial to salvage from that.
            if failures.isEmpty, !answer.failures.isEmpty {
                throw GitHubError.graphQL(answer.failures.map(\.message))
            }
            let page = ListParser.results(from: payload, searches: batch, viewer: viewer)
            if let reading = ListParser.budget(from: payload) {
                spent += reading.cost
                budget = reading
            }

            // Totals from the first round only: every page repeats them, and
            // only the first round covers every search.
            if isFirstRound { results.totals = page.totals }
            isFirstRound = false
            results.absorb(page)

            let stops = ListParser.pages(from: payload, searches: batch)
            round = round.enumerated().compactMap { position, entry in
                guard let cursor = stops[position]?.cursor else { return nil }
                guard results.count(in: entry.search.listID) < ListQuery.maximumItems else {
                    stoppedAtCap.insert(entry.search.listID)
                    return nil
                }
                return (entry.search, cursor)
            }
        }

        // Anything still asking for pages when the rounds ran out was cut
        // short as surely as one that hit the row cap.
        for entry in round { stoppedAtCap.insert(entry.search.listID) }

        return (results, results.unread(stoppedAt: stoppedAtCap), budget?.costing(spent), failures)
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
