import Foundation

/// Owns the token, the refresh timer and the path from API to `AppState`.
@MainActor
public final class RefreshController {
    private let state: AppState
    private var service: GitHubService?
    private var timer: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?

    public init(state: AppState) {
        self.state = state
    }

    // MARK: - Lifecycle

    /// Picks up a stored token and starts refreshing. Safe to call once at
    /// launch; does nothing harmful when no token is stored.
    public func start() {
        do {
            guard let token = try Keychain.readToken(), !token.isEmpty else {
                state.hasToken = false
                return
            }
            adopt(token: token)
        } catch {
            state.hasToken = false
            state.loadState = .failed("Keychain unavailable: \(error.localizedDescription)")
            return
        }

        Task { await refresh() }
        restartTimer()
    }

    private func adopt(token: String) {
        service = GitHubService(token: token)
        state.hasToken = true
    }

    /// Restarts the periodic refresh, e.g. after the interval is changed.
    public func restartTimer() {
        timer?.cancel()
        let interval = max(Settings.minimumRefreshInterval, state.settings.refreshInterval)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
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

            try Keychain.writeToken(trimmed)
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
            state.loadState = .loaded(.now)
        } catch let error as GitHubError {
            Log.api.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            state.loadState = .failed(error.localizedDescription)
        } catch {
            state.loadState = .failed(error.localizedDescription)
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
