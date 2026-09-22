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

    public func signOut() {
        try? Keychain.deleteToken()
        stop()
        service = nil
        state.viewer = nil
        state.hasToken = false
        state.listPullRequests = [:]
        state.listIssues = [:]
        state.notifications = []
        state.loadState = .idle
    }

    // MARK: - Refresh

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

        state.loadState = .loading
        do {
            // The login is needed for the search qualifiers; resolve it once
            // and keep it for later refreshes.
            let viewer: Viewer
            if let known = state.viewer {
                viewer = known
            } else {
                viewer = try await service.viewer()
                state.viewer = viewer
            }

            // The viewer is resolved for the teams and for `@me` to mean
            // something to GitHub, not to be pasted into the queries.
            _ = viewer

            let results = try await service.lists(searches())
            state.listPullRequests = results.pullRequests
            state.listIssues = results.issues

            // A row that is gone takes its detail with it -- and the pane
            // describing it, which would otherwise sit there for good.
            let livePullRequests = Set(state.allPullRequests.map(\.id))
            state.pullRequestDetails = state.pullRequestDetails.filter {
                livePullRequests.contains($0.key)
            }
            if let inspected = state.inspectedPullRequestID, !livePullRequests.contains(inspected) {
                state.inspectedPullRequestID = nil
            }

            let liveIssues = Set(state.allIssues.map(\.id))
            state.issueDetails = state.issueDetails.filter { liveIssues.contains($0.key) }
            if let inspected = state.inspectedIssueID, !liveIssues.contains(inspected) {
                state.inspectedIssueID = nil
            }

            let fetch = try await service.notifications(since: lastModified)
            lastModified = fetch.lastModified
            githubPollInterval = fetch.pollInterval
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
            state.myTrends = .unconfigured
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
                let opened = try await openedTask
                let merged = try await mergedTask

                fresh.buckets.append(
                    TrendMath.myBucket(
                        period: period,
                        opened: opened.facts,
                        merged: merged.timings
                    )
                )
                fresh.fetchedAt = .now
                state.myTrends = .loading(fresh)

                if let remaining = opened.remainingQuota ?? merged.remainingQuota,
                   remaining < Self.quotaFloor {
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
            let entries = try await service.repositoryPullRequests(repository)
            state.dashboard = .loaded(DashboardData.summarise(entries, repository: repository))
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
                from: state.expandedNotificationID,
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
        state.expandedNotificationID = nil
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
            } catch let error as GitHubError {
                Log.api.error("detail failed: \(error.localizedDescription, privacy: .public)")
                self?.state.pullRequestDetails[id] = .failed(error.localizedDescription)
            } catch {
                self?.state.pullRequestDetails[id] = .failed(error.localizedDescription)
            }
        }
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

    /// Opens or closes a preview, fetching the comment body the first time.
    ///
    /// Used where the message is shown inline -- the popover. The window
    /// selects instead, so that opening one notification closes the last.
    public func togglePreview(for item: NotificationItem) {
        guard state.expandedNotificationID != item.id else {
            state.expandedNotificationID = nil
            return
        }
        inspect(item)
    }

    /// Shows a notification in the detail pane.
    public func inspect(_ item: NotificationItem) {
        state.expandedNotificationID = item.id
        loadPreviewIfNeeded(for: item)
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
            if state.expandedNotificationID == item.id {
                state.expandedNotificationID = nil
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
