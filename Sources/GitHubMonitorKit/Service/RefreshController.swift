import Foundation

/// Owns the token, the refresh timer and the path from API to `AppState`.
@MainActor
public final class RefreshController {
    private let state: AppState
    private(set) var service: GitHubService?
    private var timer: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    /// Passed back as If-Modified-Since so unchanged polls cost no rate limit.
    private var lastModified: String?
    /// GitHub's requested minimum interval, which overrides a shorter setting.
    private var githubPollInterval: TimeInterval?

    public init(state: AppState) {
        self.state = state
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
        state.pullRequests = []
        state.notifications = []
        state.availableTeams = []
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

            let pullRequests = try await service.pullRequests(
                login: viewer.login,
                teamSlugs: state.settings.teamSlugs,
                repositoryFilters: state.settings.repositoryFilters
            )
            state.pullRequests = pullRequests
            let livePullRequests = Set(pullRequests.map(\.id))
            state.pullRequestDetails = state.pullRequestDetails.filter {
                livePullRequests.contains($0.key)
            }
            if let inspected = state.inspectedPullRequestID, !livePullRequests.contains(inspected) {
                state.inspectedPullRequestID = nil
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
            }

            state.loadState = .loaded(.now)
        } catch let error as GitHubError {
            Log.api.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            state.loadState = .failed(error.localizedDescription)
        } catch {
            state.loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Pull request detail

    /// Opens the detail pane for a pull request, fetching its detail the
    /// first time.
    public func inspect(_ item: PullRequestItem) {
        state.inspectedPullRequestID = item.id
        loadDetail(for: item.id)
    }

    public func closeInspector() {
        state.inspectedPullRequestID = nil
    }

    /// Refetches even when a detail is cached, for the pane's reload button.
    public func reloadDetail(for id: String) {
        state.pullRequestDetails[id] = nil
        loadDetail(for: id)
    }

    private func loadDetail(for id: String) {
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

    // MARK: - Notifications

    /// Opens or closes a preview, fetching the comment body the first time.
    public func togglePreview(for item: NotificationItem) {
        guard state.expandedNotificationID != item.id else {
            state.expandedNotificationID = nil
            return
        }
        state.expandedNotificationID = item.id

        // Already fetched, or being fetched: nothing more to do.
        guard state.previews[item.id] == nil else { return }

        guard let url = item.latestCommentAPIURL else {
            // Review requests and state changes have no comment to show.
            state.previews[item.id] = .empty
            return
        }

        state.previews[item.id] = .loading
        Task { [weak self] in
            guard let self, let service = self.service else { return }
            do {
                let body = try await service.commentBody(at: url)
                self.state.previews[item.id] = body.map(PreviewState.text) ?? .empty
            } catch let error as GitHubError {
                self.state.previews[item.id] = .failed(error.localizedDescription)
            } catch {
                self.state.previews[item.id] = .failed(error.localizedDescription)
            }
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

    /// Loads the user's team memberships for the settings checklist.
    public func loadTeams() async -> GitHubError? {
        guard let service else { return .noToken }
        do {
            state.availableTeams = try await service.teams()
            return nil
        } catch let error as GitHubError {
            return error
        } catch {
            return .transport(error.localizedDescription)
        }
    }
}
