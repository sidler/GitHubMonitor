import Foundation

/// Owns the token, the refresh timer and the path from API to `AppState`.
@MainActor
public final class RefreshController {
    private let state: AppState
    private let trendStore: TrendStore
    private(set) var service: GitHubService?
    private var timer: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    /// The trends load, kept so a change of repository or resolution can
    /// call off the one still running.
    private var trendsTask: Task<Void, Never>?
    private var myTrendsTask: Task<Void, Never>?
    private var commentersTask: Task<Void, Never>?
    /// Passed back as If-Modified-Since so unchanged polls cost no rate limit.
    private var lastModified: String?
    /// GitHub's requested minimum interval, which overrides a shorter setting.
    private var githubPollInterval: TimeInterval?

    public init(state: AppState, trendStore: TrendStore = TrendStore()) {
        self.state = state
        self.trendStore = trendStore
    }

    // MARK: - Lifecycle

    /// Picks up a stored token and starts refreshing. Safe to call once at
    /// launch; does nothing harmful when no token is stored.
    /// Reports whether a usable token was found, so the caller can decide
    /// whether to put the user in front of the token field.
    ///
    /// Reads the keychain off the main actor on purpose: that read can put an
    /// authorisation dialog on screen, and doing it synchronously freezes the
    /// whole interface — including the window behind the dialog — until the
    /// user answers.
    @discardableResult
    public func start() async -> Bool {
        let result = await Task.detached(priority: .userInitiated) {
            Result { try Keychain.readToken() }
        }.value

        switch result {
        case .success(let token):
            guard let token, !token.isEmpty else {
                state.hasToken = false
                return false
            }
            adopt(token: token)
            // Not awaited: the first refresh should not hold up the window.
            Task { await refresh() }
            // The dashboard may already be on screen and waiting for this.
            if case .unconfigured = state.dashboard,
               !state.settings.dashboardRepository.isEmpty
            {
                Task { await loadDashboard() }
            }
            restartTimer()
            return true

        case .failure(let error):
            state.hasToken = false
            state.loadState = .failed("Keychain unavailable: \(error.localizedDescription)")
            return false
        }
    }

    private func adopt(token: String) {
        service = GitHubService(token: token)
        state.hasToken = true
    }

    /// Restarts the periodic refresh, e.g. after the interval is changed.
    public func restartTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.effectiveInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    /// The user's interval, floored by our own minimum and by whatever GitHub
    /// asks for in `X-Poll-Interval`. Polling faster than GitHub requests is
    /// what gets clients throttled.
    var effectiveInterval: TimeInterval {
        max(
            state.settings.refreshInterval,
            max(Settings.minimumRefreshInterval, githubPollInterval ?? 0)
        )
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        inFlight?.cancel()
    }

    // MARK: - Token

    /// Stores a token, verifies it and reports what is wrong if anything is.
    /// Returns the viewer on success so the caller can show who signed in.
    @discardableResult
    public func signIn(token: String) async -> Result<Viewer, GitHubError> {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.noToken) }

        let candidate = GitHubService(token: trimmed)
        do {
            let viewer = try await candidate.viewer()
            guard viewer.scopes.isComplete else {
                // Deliberately not stored: a token that cannot do the job
                // would leave the app in a permanently failing state.
                return .failure(.missingScopes(viewer.scopes.missing))
            }

            try await Task.detached(priority: .userInitiated) {
                try Keychain.writeToken(trimmed)
            }.value
            service = candidate
            state.viewer = viewer
            state.hasToken = true
            await refresh()
            restartTimer()
            return .success(viewer)
        } catch let error as GitHubError {
            Log.api.error("sign-in failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    /// Forgets the token and everything it fetched.
    ///
    /// All of it, not just the lists: a diff left open belongs to a private
    /// repository, and so do the details, previews and charts behind it.
    /// Signing out has to leave nothing of the account on screen or in
    /// memory.
    public func signOut() {
        try? Keychain.deleteToken()
        stop()
        service = nil
        approvedByViewer = [:]
        lastModified = nil

        state.viewer = nil
        state.hasToken = false
        state.listPullRequests = [:]
        state.listIssues = [:]
        state.listUnread = [:]
        state.notifications = []
        state.previews = [:]
        state.linkedSummaries = [:]
        state.bodyLinks.clear()
        linksInFlight = []
        state.notificationThreads = [:]
        state.pullRequestDetails = [:]
        state.issueDetails = [:]
        state.changedFiles = [:]
        state.viewedFiles = [:]
        state.openedDiff = nil
        state.approval = .idle
        state.inspectedPullRequestID = nil
        state.inspectedIssueID = nil
        state.inspectedNotificationID = nil
        state.expandedNotificationID = nil
        state.workloadSelection = nil
        state.dashboard = .unconfigured
        state.trends = .unconfigured
        state.myTrends = .unconfigured
        state.repositoryCommenters = .unconfigured
        state.budgets = RateBudgets()
        state.lastRefreshCost = nil
        state.listFailures = [:]
        state.loadState = .idle
    }

    // MARK: - Refresh

    /// Pull requests this person approved from here, and when. Kept until
    /// GitHub's own answers show the approval, because until then a refresh
    /// would put the row back the way it was before it.
    private var approvedByViewer: [String: Date] = [:]

    /// Coalesces concurrent calls: a manual refresh during a scheduled one
    /// joins it rather than issuing a second set of requests.
    public func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// The searches this refresh runs.
    ///
    /// Only the lists that are shown somewhere: one that appears in neither
    /// the menu bar, the popover nor the window is a list nobody is looking
    /// at, and every search costs a request. Switching one back on triggers
    /// a refresh, so it fills in at once rather than at the next tick.
    private func searches() -> [ListSearch] {
        state.settings.savedLists
            .filter {
                $0.isRunnable && state.settings.listVisibility.isShownAnywhere($0.id)
            }
            .flatMap {
                ListQuery.searches(
                    for: $0,
                    repositoryFilters: state.settings.repositoryFilters
                )
            }
    }

    private func performRefresh() async {
        guard let service else {
            state.loadState = .failed(GitHubError.noToken.localizedDescription)
            return
        }

        // Sit a refresh out rather than run into the wall: every list would
        // fail at once, and the last known state is worth more than a screen
        // of errors. The charts already stop short of this for the same
        // reason, one threshold higher.
        if state.budgets.shouldPause() {
            state.loadState = .paused(until: state.budgets.graphQL?.resetAt)
            return
        }

        state.loadState = .loading
        do {
            // The login is needed for the search qualifiers; resolve it once
            // and keep it for later refreshes.
            let viewer: Viewer
            if let known = state.viewer {
                viewer = known
            } else {
                viewer = try await service.viewer()
                guard !Task.isCancelled else { return }
                state.viewer = viewer
            }

            // Not pasted into the queries -- `@me` means something to
            // GitHub already -- but the review requests come back naming
            // people, and only the login says which of them is this person.
            let fetched = try await service.lists(searches(), viewer: viewer.login)
            // Cancelled means the token is going or the app is closing.
            // Writing what came back would put a signed-out account's rows
            // back on screen, so nothing is written past this point.
            guard !Task.isCancelled else { return }

            let results = fetched.results
            if let budget = fetched.budget {
                state.budgets.graphQL = budget
                // What GitHub charged for this refresh, for the sentence in
                // settings. Its own figure, not the difference between two
                // readings: details, diffs and linked summaries are fetched
                // between refreshes, and a difference would charge the
                // refresh for those as well.
                state.lastRefreshCost = budget.cost
            }
            state.listPullRequests = results.pullRequests
            state.listIssues = results.issues
            state.listUnread = fetched.unread
            state.listFailures = fetched.failures
            applyOwnApprovals()

            // A row that is gone takes its detail with it -- and the pane
            // describing it, which would otherwise sit there for good.
            let livePullRequests = Set(state.allPullRequests.map(\.id))
            state.pullRequestDetails = state.pullRequestDetails.filter {
                livePullRequests.contains($0.key)
            }
            state.changedFiles = state.changedFiles.filter { livePullRequests.contains($0.key) }
            state.viewedFiles = state.viewedFiles.filter { livePullRequests.contains($0.key) }
            if let inspected = state.inspectedPullRequestID, !livePullRequests.contains(inspected) {
                state.inspectedPullRequestID = nil
            }

            // Descriptions already read for numbers go with their rows.
            state.bodyLinks.keep(livePullRequests.union(Set(state.allIssues.map(\.id))))

            let liveIssues = Set(state.allIssues.map(\.id))
            state.issueDetails = state.issueDetails.filter { liveIssues.contains($0.key) }
            if let inspected = state.inspectedIssueID, !liveIssues.contains(inspected) {
                state.inspectedIssueID = nil
            }

            let fetch = try await service.notifications(since: lastModified)
            guard !Task.isCancelled else { return }
            lastModified = fetch.lastModified
            githubPollInterval = fetch.pollInterval
            if let budget = fetch.budget { state.budgets.rest = budget }
            // A 304 means nothing changed; keeping the current list is the
            // point of asking conditionally.
            if let items = fetch.items {
                state.notifications = items
                // Drop previews for threads that are gone, so the cache does
                // not grow for the life of the process.
                let live = Set(items.map(\.id))
                state.previews = state.previews.filter { live.contains($0.key) }
                prefetchPreviews()
            }

            state.loadState = .loaded(.now)
        } catch let error as GitHubError {
            Log.api.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            state.loadState = .failed(error.localizedDescription)
        } catch {
            state.loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Trends

    /// The lowest GraphQL budget the trends fetch will start another period
    /// on. A year of history is the app's most expensive request by far,
    /// and the lists people actually work from must not go dark because a
    /// chart ate the hour's quota.
    static let quotaFloor = 500

    /// Loads the trend charts, one period at a time.
    ///
    /// Publishes after every period so the charts fill in as they arrive:
    /// a year of history takes long enough that a spinner would be the
    /// wrong answer. A cached history is shown first and refreshed behind
    /// it, so the view is never empty when something is known.
    public func loadTrends(force: Bool = false) async {
        // Switching the resolution while a year is still coming in would
        // otherwise leave two loads writing periods into the same charts.
        trendsTask?.cancel()
        let task = Task { await performTrendsLoad(force: force) }
        trendsTask = task
        await task.value
    }

    private func performTrendsLoad(force: Bool) async {
        let repository = state.settings.dashboardRepository
            .trimmingCharacters(in: .whitespaces)
        let resolution = state.settings.trendResolution

        guard !repository.isEmpty else {
            state.trends = .unconfigured
            return
        }

        let cached = trendStore.load(repository: repository, resolution: resolution)
        if let cached, !force, !cached.isStale, cached.isComplete {
            state.trends = .loaded(cached)
            return
        }

        guard let service else {
            state.trends = .failed(GitHubError.noToken.localizedDescription)
            return
        }

        // Whatever is known stays on screen while the periods come in.
        state.trends = .loading(cached)

        var fresh = TrendData(repository: repository, resolution: resolution)
        for period in TrendMath.periods(resolution) {
            guard !Task.isCancelled else { return }
            do {
                // The two halves of a period do not depend on each other,
                // and a period is slow enough to be worth halving. Periods
                // themselves stay sequential: GitHub asks that requests for
                // one user go one after another.
                async let mergedTask = service.mergedTimings(
                    repository: repository,
                    period: period
                )
                async let openedTask = service.openedCounts(
                    repository: repository,
                    period: period
                )
                let merged = try await mergedTask
                let opened = try await openedTask

                fresh.buckets.append(
                    TrendMath.bucket(
                        period: period,
                        merged: merged.timings,
                        openedByPeople: opened.byPeople,
                        openedByEveryone: opened.byEveryone
                    )
                )
                fresh.fetchedAt = .now
                state.trends = .loading(fresh)

                // Stop while there is still enough budget for the lists.
                if let remaining = opened.remainingQuota ?? merged.remainingQuota,
                   remaining < Self.quotaFloor {
                    fresh.truncationReason =
                        "Stopped after \(fresh.buckets.count) periods: GitHub's hourly query budget was running low."
                    break
                }
            } catch let error as GitHubError {
                // Periods already fetched are worth showing; only the empty
                // case is a failure.
                guard !fresh.buckets.isEmpty else {
                    state.trends = .failed(error.localizedDescription)
                    return
                }
                fresh.truncationReason = error.localizedDescription
                break
            } catch {
                guard !fresh.buckets.isEmpty else {
                    state.trends = .failed(error.localizedDescription)
                    return
                }
                fresh.truncationReason = error.localizedDescription
                break
            }
        }

        guard !Task.isCancelled else { return }
        state.trends = .loaded(fresh)
        trendStore.save(fresh)
    }

    /// Loads the charts about one's own pull requests, period by period.
    ///
    /// Same shape as the repository trends -- cached, published as the
    /// periods arrive, stopping if the quota runs low -- but scoped to the
    /// signed-in user and to whatever repository filters the lists work
    /// under, so it describes the same body of work.
    public func loadMyTrends(force: Bool = false) async {
        myTrendsTask?.cancel()
        let task = Task { await performMyTrendsLoad(force: force) }
        myTrendsTask = task
        await task.value
    }

    private func performMyTrendsLoad(force: Bool) async {
        guard let service else {
            // A refresh that cannot run should not erase what is on screen.
            // Everywhere else here follows the same rule: a 304 keeps the
            // list, and a failed period keeps the ones already fetched.
            if state.myTrends.data == nil { state.myTrends = .unconfigured }
            return
        }

        let login: String
        if let viewer = state.viewer {
            login = viewer.login
        } else {
            do {
                let viewer = try await service.viewer()
                state.viewer = viewer
                login = viewer.login
            } catch {
                state.myTrends = .failed(error.localizedDescription)
                return
            }
        }

        let resolution = state.settings.trendResolution
        let cached = trendStore.loadMine(login: login, resolution: resolution)
        if let cached, !force, !cached.isStale, cached.isComplete {
            state.myTrends = .loaded(cached)
            return
        }

        state.myTrends = .loading(cached)

        let filters = state.settings.repositoryFilters
        var fresh = MyTrendData(login: login, resolution: resolution)
        for period in TrendMath.periods(resolution) {
            guard !Task.isCancelled else { return }
            do {
                async let openedTask = service.myPullRequests(
                    matching: MyTrendQuery.openedQuery(
                        login: login,
                        repositoryFilters: filters,
                        period: period
                    )
                )
                async let mergedTask = service.mergedTimings(
                    matching: MyTrendQuery.mergedQuery(
                        login: login,
                        repositoryFilters: filters,
                        period: period
                    )
                )
                async let answeredTask = service.reviewResponses(
                    matching: MyTrendQuery.reviewedQuery(
                        login: login,
                        repositoryFilters: filters,
                        period: period
                    ),
                    viewer: login
                )
                let opened = try await openedTask
                let merged = try await mergedTask
                let answered = try await answeredTask

                fresh.buckets.append(
                    TrendMath.myBucket(
                        period: period,
                        opened: opened.facts,
                        merged: merged.timings,
                        responses: answered.responses
                    )
                )
                fresh.fetchedAt = .now
                state.myTrends = .loading(fresh)

                let quota = [opened.remainingQuota, merged.remainingQuota, answered.remainingQuota]
                    .compactMap { $0 }
                    .min()
                if let quota, quota < Self.quotaFloor {
                    fresh.truncationReason =
                        "Stopped after \(fresh.buckets.count) periods: GitHub's hourly query budget was running low."
                    break
                }
            } catch {
                guard !fresh.buckets.isEmpty else {
                    state.myTrends = .failed(error.localizedDescription)
                    return
                }
                fresh.truncationReason = error.localizedDescription
                break
            }
        }

        guard !Task.isCancelled else { return }
        state.myTrends = .loaded(fresh)
        trendStore.save(fresh)
    }

    /// Reads who comments across the whole dashboard repository.
    ///
    /// Its own fetch, and only when that side of the switch is showing: it
    /// covers every pull request in the repository rather than the handful
    /// you opened, which is a different order of magnitude.
    public func loadRepositoryCommenters(force: Bool = false) async {
        commentersTask?.cancel()
        let task = Task { await performCommentersLoad(force: force) }
        commentersTask = task
        await task.value
    }

    private func performCommentersLoad(force: Bool) async {
        let repository = state.settings.dashboardRepository
            .trimmingCharacters(in: .whitespaces)
        guard !repository.isEmpty else {
            state.repositoryCommenters = .unconfigured
            return
        }

        let resolution = state.settings.trendResolution
        let cached = trendStore.loadCommenters(repository: repository, resolution: resolution)
        if let cached, !force, !cached.isStale, cached.isComplete {
            state.repositoryCommenters = .loaded(cached)
            return
        }

        guard let service else {
            state.repositoryCommenters = .failed(GitHubError.noToken.localizedDescription)
            return
        }

        state.repositoryCommenters = .loading(cached)

        var fresh = CommenterData(repository: repository, resolution: resolution)
        for period in TrendMath.periods(resolution) {
            guard !Task.isCancelled else { return }
            do {
                let page = try await service.myPullRequests(
                    matching: MyTrendQuery.repositoryQuery(repository: repository, period: period)
                )
                fresh.add(page.facts)
                state.repositoryCommenters = .loading(fresh)

                if let remaining = page.remainingQuota, remaining < Self.quotaFloor {
                    fresh.truncationReason =
                        "Stopped after \(fresh.periodsRead) periods: GitHub's hourly query budget was running low."
                    break
                }
            } catch {
                guard fresh.periodsRead > 0 else {
                    state.repositoryCommenters = .failed(error.localizedDescription)
                    return
                }
                fresh.truncationReason = error.localizedDescription
                break
            }
        }

        guard !Task.isCancelled else { return }
        state.repositoryCommenters = .loaded(fresh)
        trendStore.save(fresh)
    }

    // MARK: - Dashboard

    /// Loads every open pull request in the dashboard repository.
    ///
    /// Separate from the refresh cycle: it covers a whole repository rather
    /// than the user's own queue, and is only worth fetching while that view
    /// is open.
    public func loadDashboard() async {
        let repository = state.settings.dashboardRepository
            .trimmingCharacters(in: .whitespaces)
        guard !repository.isEmpty else {
            state.dashboard = .unconfigured
            return
        }
        guard let service else {
            // The token is read asynchronously at launch, so this view can
            // open before it arrives. Staying unconfigured lets the reload
            // below pick it up, rather than showing a spurious failure.
            state.dashboard = .unconfigured
            return
        }

        state.dashboard = .loading
        do {
            let fetched = try await service.repositoryPullRequests(repository)
            if let budget = fetched.budget { state.budgets.graphQL = budget }
            state.dashboard = .loaded(DashboardData.summarise(
                fetched.entries,
                repository: repository,
                unread: fetched.unread
            ))
        } catch let error as GitHubError {
            Log.api.error("dashboard failed: \(error.localizedDescription, privacy: .public)")
            state.dashboard = .failed(error.localizedDescription)
        } catch {
            state.dashboard = .failed(error.localizedDescription)
        }
    }

    // MARK: - Pull request detail

    /// Opens the detail pane for a pull request, fetching its detail the
    /// first time.
    public func inspect(_ item: PullRequestItem) {
        state.inspectedPullRequestID = item.id
        loadDetailIfNeeded(for: item.id)
    }

    /// Moves the detail pane one row up or down the list on screen.
    ///
    /// Behind the menu items, and behind them the keyboard: a list bound to
    /// the same selection already moves with the arrow keys, but only while
    /// it has focus, and the pane should be reachable from anywhere in the
    /// window.
    public func moveInspection(by offset: Int) {
        switch state.sidebarSelection {
        case .list:
            switch state.selectedList?.content {
            case .pullRequests:
                if let next = Self.step(
                    state.inspectableItems,
                    from: state.inspectedPullRequestID,
                    by: offset
                ) {
                    inspect(next)
                }
            case .issues:
                if let next = Self.step(
                    state.inspectableIssues,
                    from: state.inspectedIssueID,
                    by: offset
                ) {
                    inspect(next)
                }
            case nil:
                break
            }
        case .mentions:
            if let next = Self.step(
                state.inspectableNotifications,
                from: state.inspectedNotificationID,
                by: offset
            ) {
                inspect(next)
            }
        case .dashboard:
            if let next = Self.step(
                state.inspectableWorkload,
                from: state.workloadSelection?.id,
                by: offset
            ) {
                state.workloadSelection = next
            }
        case .trends, .myTrends, .settings:
            break
        }
    }

    /// The row `offset` steps along from the one open now.
    ///
    /// Stops at the ends rather than wrapping: a list that jumps from the
    /// last row back to the first loses the reader's place, and in a long
    /// queue it is not even visible that it happened.
    static func step<Item: Identifiable>(
        _ items: [Item],
        from current: Item.ID?,
        by offset: Int
    ) -> Item? {
        guard !items.isEmpty else { return nil }
        guard
            let current,
            let index = items.firstIndex(where: { $0.id == current })
        else {
            // Nothing open yet: start at the end the user is heading for.
            return offset < 0 ? items.last : items.first
        }
        let next = index + offset
        return items.indices.contains(next) ? items[next] : nil
    }

    /// Closes whichever detail the pane is showing.
    public func closeInspector() {
        state.inspectedPullRequestID = nil
        state.inspectedIssueID = nil
        state.inspectedNotificationID = nil
        state.workloadSelection = nil
    }

    /// Lists a workload bar's pull requests, or puts them away when that bar
    /// is the one already open.
    ///
    /// Clicking the same bar twice closes the pane: a chart has no row to
    /// click away from, so without this the only way out would be the pane's
    /// own button.
    public func toggleWorkload(_ selection: WorkloadSelection) {
        state.workloadSelection = state.workloadSelection == selection ? nil : selection
    }

    /// Refetches even when a detail is cached, for the pane's reload button.
    public func reloadDetail(for id: String) {
        state.pullRequestDetails[id] = nil
        state.changedFiles[id] = nil
        loadDetailIfNeeded(for: id)
    }

    /// Fetches a pull request's detail unless it is already there.
    ///
    /// Public because the selection can move without going through
    /// `inspect`: the list is bound straight to it, so the arrow keys change
    /// the id and the window controller asks for the payload afterwards.
    public func loadDetailIfNeeded(for id: String) {
        // Already fetched or in flight.
        guard state.pullRequestDetails[id] == nil else { return }
        guard let service else {
            state.pullRequestDetails[id] = .failed(GitHubError.noToken.localizedDescription)
            return
        }

        state.pullRequestDetails[id] = .loading
        Task { [weak self] in
            do {
                let detail = try await service.pullRequestDetail(id: id)
                self?.state.pullRequestDetails[id] = .loaded(detail)
                // A detail fetched moments after approving can still answer
                // with the review set from before it.
                self?.applyOwnApprovals()
            } catch let error as GitHubError {
                Log.api.error("detail failed: \(error.localizedDescription, privacy: .public)")
                self?.state.pullRequestDetails[id] = .failed(error.localizedDescription)
            } catch {
                self?.state.pullRequestDetails[id] = .failed(error.localizedDescription)
            }
        }

        loadFilesIfNeeded(for: id)
    }

    /// The files a pull request touches, fetched beside its detail.
    ///
    /// Its own request and its own state: it goes to the REST API, which has
    /// an hourly budget of its own, and it is the slower of the two -- the
    /// rest of the pane should not wait behind a diff.
    public func loadFilesIfNeeded(for id: String) {
        guard state.changedFiles[id] == nil else { return }
        guard let service, let item = state.pullRequest(withID: id) else { return }

        state.changedFiles[id] = .loading
        loadViewedFilesIfNeeded(for: id)
        Task { [weak self] in
            do {
                let files = try await service.changedFiles(
                    repository: item.repository, number: item.number
                )
                self?.state.changedFiles[id] = .loaded(files)
            } catch let error as GitHubError {
                Log.api.error("files failed: \(error.localizedDescription, privacy: .public)")
                self?.state.changedFiles[id] = .failed(error.localizedDescription)
            } catch {
                self?.state.changedFiles[id] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Viewed files

    /// Which files GitHub says this person has ticked off.
    ///
    /// Its own request beside the patches: the patches come from REST,
    /// which does not carry the tick, and this comes from GraphQL, which
    /// does not carry the patch. Joined on the path, which is what both
    /// sides key on.
    ///
    /// A failure here is quiet. The diff is readable without the ticks, and
    /// an error banner over somebody's review for a checkbox would be worse
    /// than the missing checkbox.
    public func loadViewedFilesIfNeeded(for id: String) {
        guard state.viewedFiles[id] == nil, let service else { return }
        // Claimed straight away, so a second opening does not ask again
        // while the first is still in flight.
        state.viewedFiles[id] = [:]

        Task { [weak self] in
            do {
                let fetched = try await service.viewedFiles(pullRequestID: id)
                guard let self else { return }
                // Merged rather than assigned: a tick set while this was in
                // flight is newer than what the request went out to ask.
                state.viewedFiles[id] = fetched.states.merging(
                    state.viewedFiles[id] ?? [:]
                ) { _, mine in mine }
                if let budget = fetched.budget { state.budgets.graphQL = budget }
            } catch {
                Log.api.error("viewed files failed: \(error.localizedDescription, privacy: .public)")
                // Left empty rather than nil: asking again on every redraw
                // would spend the budget on an answer that just failed.
            }
        }
    }

    /// Ticks a file off, or takes the tick back, on GitHub and here.
    ///
    /// Shown straight away and corrected if GitHub refuses. A tick is a
    /// private, reversible note to yourself that nobody else sees, so it
    /// asks nothing first -- unlike the approval, which is public and
    /// final.
    public func setViewed(_ viewed: Bool, path: String, in pullRequestID: String) {
        guard let service else { return }
        let previous = state.viewedState(of: path, in: pullRequestID)
        guard previous != (viewed ? .viewed : .unviewed) else { return }

        state.viewedFiles[pullRequestID, default: [:]][path] = viewed ? .viewed : .unviewed

        Task { [weak self] in
            do {
                try await service.setViewed(viewed, pullRequestID: pullRequestID, path: path)
            } catch {
                Log.api.error("marking viewed failed: \(error.localizedDescription, privacy: .public)")
                // Put back what it was, rather than leave a tick on screen
                // that GitHub does not have.
                self?.state.viewedFiles[pullRequestID, default: [:]][path] = previous
            }
        }
    }

    // MARK: - Links

    /// References a request is already out for, so a second panel opening
    /// on the same link does not start a race with the first.
    private var linksInFlight: Set<String> = []

    /// Looks up the issues and pull requests named by an item, once.
    ///
    /// Only what is not already known, and only when a panel actually asks:
    /// a link nobody opens costs nothing. What comes back is kept for the
    /// run -- what an issue is about does not change between two glances at
    /// the same diff.
    public func loadLinksIfNeeded(_ references: [ItemReference]) {
        let wanted = references.filter(needsLookup)
        guard !wanted.isEmpty else { return }
        guard let service else {
            // Said rather than left spinning -- but `needsLookup` treats a
            // failure as worth another try, so a panel opened in the moment
            // before `start()` has read the keychain answers itself the
            // next time it is opened.
            for reference in wanted {
                state.linkedSummaries[reference.id] = .failed(
                    GitHubError.noToken.localizedDescription
                )
            }
            return
        }

        for reference in wanted {
            state.linkedSummaries[reference.id] = .loading
            linksInFlight.insert(reference.id)
        }

        Task { [weak self] in
            // One request per batch, in turn rather than at once: each is
            // charged, and the budget reading that comes back with the last
            // one should be the last word.
            for batch in LinkedItemQuery.batches(wanted) {
                do {
                    let fetched = try await service.linkedItems(batch)
                    guard let self else { return }
                    for reference in batch {
                        // Absent from an answer that did ask for it is the
                        // same as not there.
                        state.linkedSummaries[reference.id] =
                            fetched.summaries[reference] ?? .missing
                        linksInFlight.remove(reference.id)
                    }
                    if let budget = fetched.budget { state.budgets.graphQL = budget }
                } catch {
                    Log.api.error("links failed: \(error.localizedDescription, privacy: .public)")
                    guard let self else { return }
                    for reference in batch {
                        state.linkedSummaries[reference.id] = .failed(error.localizedDescription)
                        linksInFlight.remove(reference.id)
                    }
                }
            }
        }
    }

    /// Whether this one is worth asking about now.
    ///
    /// A failure is worth another try -- the token may have arrived since,
    /// or the network come back -- but only when nothing is already on its
    /// way for it, or the older answer would land on top of the newer one.
    private func needsLookup(_ reference: ItemReference) -> Bool {
        guard !linksInFlight.contains(reference.id) else { return false }
        switch state.linkedSummaries[reference.id] {
        case nil, .failed: return true
        case .loading, .loaded, .missing: return false
        }
    }

    /// Asks again for one link, after a failure or because it is stale.
    public func reloadLink(_ reference: ItemReference) {
        guard !linksInFlight.contains(reference.id) else { return }
        state.linkedSummaries[reference.id] = nil
        loadLinksIfNeeded([reference])
    }

    // MARK: - Approving

    /// Looks at the head commit, and puts the question up if it still
    /// matches the diff that was read.
    ///
    /// The check comes before the question rather than after: confirming
    /// something that then turns out not to have happened is worse than a
    /// moment's wait.
    public func askToApprove(_ item: PullRequestItem) async {
        guard let service else {
            state.approval = .failed(
                pullRequestID: item.id,
                message: GitHubError.noToken.localizedDescription
            )
            return
        }

        state.approval = .checking(pullRequestID: item.id)
        do {
            let head = try await service.head(of: item.id)
            if let refusal = ApprovalQuery.refusal(comparing: head, against: item.headCommit) {
                state.approval = .failed(
                    pullRequestID: item.id,
                    message: refusal.localizedDescription
                )
                return
            }
            state.approval = .confirming(pullRequestID: item.id)
        } catch {
            state.approval = .failed(pullRequestID: item.id, message: error.localizedDescription)
        }
    }

    /// Puts the question away without writing anything.
    public func cancelApproval() {
        if case .confirming = state.approval { state.approval = .idle }
    }

    /// Sends the approval, bound to the commit whose diff was on screen.
    ///
    /// Returns whether GitHub took it, so the caller can put the diff away
    /// only when something actually happened.
    @discardableResult
    public func approve(_ item: PullRequestItem) async -> Bool {
        guard let service, let commit = item.headCommit else {
            state.approval = .failed(
                pullRequestID: item.id,
                message: "This pull request has not been read since the app learned to approve. Refresh and try again."
            )
            return false
        }

        state.approval = .sending(pullRequestID: item.id)
        do {
            try await service.approve(pullRequestID: item.id, commit: commit)
            state.approval = .idle
            // Counted straight away, in the row and in the pane beside it.
            // Not the pull request's own decision: two approvals may be
            // required, and GitHub is the only one who knows.
            countApproval(of: item)
            // Not awaited. The diff closes on this returning, and the
            // refresh that replaces the guess with GitHub's own account
            // takes seconds -- holding a window open over a review that is
            // finished, to wait for a confirmation of something already
            // confirmed. The row and the pane already show the approval.
            Task { [weak self] in await self?.refreshApproved(item) }
            return true
        } catch {
            Log.api.error("approve failed: \(error.localizedDescription, privacy: .public)")
            state.approval = .failed(pullRequestID: item.id, message: error.localizedDescription)
            return false
        }
    }

    private func countApproval(of item: PullRequestItem) {
        approvedByViewer[item.id] = .now
        applyOwnApprovals()
    }

    /// Re-applies what this person has approved but GitHub has not admitted
    /// to yet.
    ///
    /// A refresh replaces the rows wholesale, and the rows come from a
    /// search -- the most lagged index GitHub has, routinely a minute or
    /// more behind a write. Without this the approval appears, the refresh
    /// lands, and it vanishes again until the index catches up, which is
    /// exactly what the optimistic count was there to prevent.
    private func applyOwnApprovals() {
        guard !approvedByViewer.isEmpty else { return }
        forgetSettledApprovals()

        for (listID, items) in state.listPullRequests {
            for (index, row) in items.enumerated() where approvedByViewer[row.id] != nil {
                guard row.viewerReview?.state != .approved else { continue }
                state.listPullRequests[listID]?[index] = row.countingViewerApproval()
            }
        }

        // The pane lists the reviewers, and it is open behind the diff that
        // was approved from.
        guard let viewer = state.viewer else { return }
        for id in approvedByViewer.keys {
            guard case .loaded(let detail) = state.pullRequestDetails[id] else { continue }
            guard !detail.reviewers.contains(where: {
                !$0.isTeam && $0.state == .approved
                    && $0.name.caseInsensitiveCompare(viewer.login) == .orderedSame
            }) else { continue }
            state.pullRequestDetails[id] = .loaded(
                detail.countingApproval(by: viewer.login, avatarURL: viewer.avatarURL)
            )
        }
    }

    /// Drops what GitHub has caught up on, and what has waited long enough
    /// that carrying it further would be asserting rather than covering.
    private func forgetSettledApprovals() {
        for (id, approvedAt) in approvedByViewer {
            let settled = state.pullRequest(withID: id)?.viewerReview?.state == .approved
            if settled || Date.now.timeIntervalSince(approvedAt) > Self.approvalGrace {
                approvedByViewer[id] = nil
            }
        }
    }

    /// How long an approval of ours outlives GitHub's silence about it.
    static let approvalGrace: TimeInterval = 600

    /// Fetches the list and this one pull request again, so GitHub's own
    /// account replaces the guess as soon as it has one.
    ///
    /// The list first: it decides whether the pull request is still there at
    /// all, and a detail reloaded before that would be thrown away by the
    /// pruning that follows it. Whatever the refresh brings back, the
    /// approval is put back on top of it until GitHub reports it too.
    private func refreshApproved(_ item: PullRequestItem) async {
        await refresh()
        guard state.pullRequest(withID: item.id) != nil else { return }
        state.pullRequestDetails[item.id] = nil
        loadDetailIfNeeded(for: item.id)
    }

    // MARK: - Issues

    /// Opens the detail pane for an issue, fetching its body the first time.
    public func inspect(_ item: IssueItem) {
        state.inspectedIssueID = item.id
        loadIssueDetailIfNeeded(for: item.id)
    }

    /// Refetches a cached issue detail, for the pane's reload button.
    public func reloadIssueDetail(for id: String) {
        state.issueDetails[id] = nil
        loadIssueDetailIfNeeded(for: id)
    }

    /// Fetches an issue's body and the end of its thread unless they are
    /// already there.
    ///
    /// Public for the same reason as the pull request detail: the list is
    /// bound straight to the selection, so the arrow keys open an issue
    /// without anything having asked for its text.
    public func loadIssueDetailIfNeeded(for id: String) {
        guard state.issueDetails[id] == nil else { return }
        guard let service else {
            state.issueDetails[id] = .failed(GitHubError.noToken.localizedDescription)
            return
        }

        state.issueDetails[id] = .loading
        Task { [weak self] in
            do {
                let detail = try await service.issueDetail(id: id)
                self?.state.issueDetails[id] = .loaded(detail)
            } catch let error as GitHubError {
                Log.api.error("issue detail failed: \(error.localizedDescription, privacy: .public)")
                self?.state.issueDetails[id] = .failed(error.localizedDescription)
            } catch {
                self?.state.issueDetails[id] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Notifications

    /// Opens or closes a message inline in the popover.
    ///
    /// The popover has nowhere else to put it, so it expands the row; the
    /// window has a pane and uses `inspect` instead. The two are kept apart
    /// on purpose -- reading one in the popover should not rearrange a
    /// window behind it.
    public func togglePreview(for item: NotificationItem) {
        guard state.expandedNotificationID != item.id else {
            state.expandedNotificationID = nil
            return
        }
        state.expandedNotificationID = item.id
        loadPreviewIfNeeded(for: item)
    }

    /// Shows a notification in the window's detail pane.
    public func inspect(_ item: NotificationItem) {
        state.inspectedNotificationID = item.id
        loadPreviewIfNeeded(for: item)
        loadThreadIfNeeded(for: item)
    }

    /// Fetches the conversation behind a notification unless it is already
    /// there.
    ///
    /// Only for the window's pane: the popover expands a row to a few lines
    /// and the single comment it already has is enough for that.
    public func loadThreadIfNeeded(for item: NotificationItem) {
        guard state.notificationThreads[item.id] == nil else { return }
        guard let url = item.subjectAPIURL, ThreadQuery.subject(from: url) != nil else {
            // A commit or a release has no conversation to read; the pane
            // falls back to the message the notification carries.
            state.notificationThreads[item.id] = .failed("No conversation to show")
            return
        }
        guard let service else {
            state.notificationThreads[item.id] = .failed(GitHubError.noToken.localizedDescription)
            return
        }

        state.notificationThreads[item.id] = .loading
        Task { [weak self] in
            do {
                let thread = try await service.thread(at: url)
                self?.state.notificationThreads[item.id] = .loaded(thread)
            } catch let error as GitHubError {
                Log.api.error("thread failed: \(error.localizedDescription, privacy: .public)")
                self?.state.notificationThreads[item.id] = .failed(error.localizedDescription)
            } catch {
                self?.state.notificationThreads[item.id] = .failed(error.localizedDescription)
            }
        }
    }

    /// Refetches a conversation, for the pane's reload button.
    public func reloadThread(for item: NotificationItem) {
        state.notificationThreads[item.id] = nil
        loadThreadIfNeeded(for: item)
    }

    /// Fetches a notification's message unless it is already there.
    ///
    /// Public for the same reason as the pull request detail: the list is
    /// bound straight to the selection, so the arrow keys open a
    /// notification without anything having asked for its body.
    public func loadPreviewIfNeeded(for item: NotificationItem) {
        // Already fetched, or being fetched: nothing more to do.
        guard state.previews[item.id] == nil else { return }
        guard item.latestCommentAPIURL != nil else {
            // Nothing to fetch, so nothing to wait for: a review request or
            // a state change has no comment, and a spinner in its place
            // would never resolve.
            state.previews[item.id] = .loaded(.none)
            return
        }
        state.previews[item.id] = .loading
        Task { [weak self] in await self?.fetchPreview(for: item) }
    }

    /// Reads the comments behind the notifications just loaded.
    ///
    /// The list names the sender, and the notifications API does not: the
    /// only place a person's name appears is the comment itself. Fetching
    /// them up front is what lets every row say who wrote it rather than
    /// only the row that happens to be open.
    ///
    /// Once per thread, not once per refresh -- the cache is keyed by
    /// thread id, so a steady inbox costs nothing. Capped and sequential,
    /// because an inbox left alone for a week should not turn one refresh
    /// into a burst of requests.
    private func prefetchPreviews() {
        var fetchable: [NotificationItem] = []
        for item in state.notifications where state.previews[item.id] == nil {
            guard item.latestCommentAPIURL != nil else {
                state.previews[item.id] = .loaded(.none)
                continue
            }
            guard fetchable.count < Self.previewPrefetchLimit else { continue }
            // Claimed before the fetching starts, so a row opened meanwhile
            // does not ask for the same comment a second time.
            state.previews[item.id] = .loading
            fetchable.append(item)
        }

        guard !fetchable.isEmpty else { return }
        Task { [weak self] in
            for item in fetchable { await self?.fetchPreview(for: item) }
        }
    }

    static let previewPrefetchLimit = 25

    private func fetchPreview(for item: NotificationItem) async {
        guard let url = item.latestCommentAPIURL else {
            // Review requests and state changes have no comment to show,
            // and no sender either.
            state.previews[item.id] = .loaded(.none)
            return
        }
        guard let service else {
            state.previews[item.id] = .failed(GitHubError.noToken.localizedDescription)
            return
        }

        do {
            state.previews[item.id] = .loaded(try await service.comment(at: url))
        } catch let error as GitHubError {
            state.previews[item.id] = .failed(error.localizedDescription)
        } catch {
            state.previews[item.id] = .failed(error.localizedDescription)
        }
    }

    /// Marks a thread read on GitHub and removes it locally.
    ///
    /// This is a write that also empties the thread from the GitHub web inbox,
    /// so it runs only from an explicit button press.
    public func markRead(_ item: NotificationItem) async {
        guard let service else { return }
        do {
            try await service.markRead(threadID: item.id)
            state.notifications.removeAll { $0.id == item.id }
            state.previews[item.id] = nil
            state.notificationThreads[item.id] = nil
            // Read where it was open, whichever of the two that was.
            if state.expandedNotificationID == item.id {
                state.expandedNotificationID = nil
            }
            if state.inspectedNotificationID == item.id {
                state.inspectedNotificationID = nil
            }
        } catch let error as GitHubError {
            state.loadState = .failed("Could not mark as read: \(error.localizedDescription)")
        } catch {
            state.loadState = .failed("Could not mark as read: \(error.localizedDescription)")
        }
    }

    /// Marks every currently visible notification read, one request each.
    public func markAllVisibleRead() async {
        for item in state.visibleNotifications {
            await markRead(item)
        }
    }
}
