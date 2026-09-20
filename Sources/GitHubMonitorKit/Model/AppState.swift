import Foundation
import Observation

public enum MainWindowTab: String, Hashable, CaseIterable, Sendable {
    case pullRequests
    case mentions
    case settings

    public var label: String {
        switch self {
        case .pullRequests: "Pull Requests"
        case .mentions: "Mentions"
        case .settings: "Settings"
        }
    }

    public var symbolName: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .mentions: "bell"
        case .settings: "gearshape"
        }
    }
}

public enum SettingsTab: String, Hashable, CaseIterable, Sendable {
    case account
    case filters
    case general
}

public enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(Date)
    case failed(String)
}

/// Single source of truth shared by the status item, the popover and the
/// main window.
@MainActor
@Observable
public final class AppState {
    public let settings: Settings

    public var pullRequests: [PullRequestItem] = []
    public var notifications: [NotificationItem] = []
    public var loadState: LoadState = .idle
    /// True once a token has been found in the Keychain.
    public var hasToken: Bool = false
    /// Who the token belongs to, once verified.
    public var viewer: Viewer?
    /// Team memberships offered as a checklist in settings.
    public var availableTeams: [TeamMembership] = []
    /// Comment bodies, fetched only when a row is opened.
    public var previews: [String: PreviewState] = [:]
    /// The notification whose preview is expanded, if any.
    public var expandedNotificationID: String?
    public var selectedTab: MainWindowTab = .pullRequests
    public var selectedSettingsTab: SettingsTab = .account

    public init(settings: Settings) {
        self.settings = settings
    }

    /// Pull requests after every filter -- what the list shows and what the
    /// menu bar counts. Both read this so they cannot drift apart.
    public var visiblePullRequests: [PullRequestItem] {
        PullRequestFilter.apply(
            pullRequests,
            includeDrafts: settings.includeDrafts,
            repositoryFilters: settings.repositoryFilters
        )
    }

    /// Notifications after every filter -- what the list shows and what the
    /// menu bar counts.
    public var visibleNotifications: [NotificationItem] {
        NotificationFilter.apply(
            notifications,
            reasons: settings.notificationReasons,
            repositoryFilters: settings.repositoryFilters
        )
    }

    /// Drafts within the repository filter, whether or not they are shown.
    /// Drives the wording of the draft toggle.
    public var draftCount: Int {
        PullRequestFilter
            .matchingRepositories(pullRequests, repositoryFilters: settings.repositoryFilters)
            .count { $0.isDraft }
    }

    public var health: StatusBarHealth {
        guard hasToken else { return .unconfigured }
        if case .failed = loadState { return .failing }
        return .ok
    }

    public var statusMessage: String {
        switch loadState {
        case .idle: "Not refreshed yet"
        case .loading: "Refreshing…"
        case .loaded(let date): "Updated \(RelativeTime.string(for: date))"
        case .failed(let message): message
        }
    }

    /// Placeholder content for stage 1, so the menu bar rendering and the two
    /// UIs can be exercised before the API clients exist.
    public func loadSampleData() {
        hasToken = true
        pullRequests = [
            PullRequestItem(
                id: "1", number: 482, title: "Fix race condition in session handler",
                repository: "octo/server", author: "mira",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4"),
                url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now.addingTimeInterval(-3600),
                reviewDecision: .reviewRequired, checks: .success
            ),
            PullRequestItem(
                id: "2", number: 77, title: "Add PSR-12 ruleset to CI",
                repository: "octo/website", author: "arun",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/2?v=4"),
                url: URL(string: "https://github.com")!, isDraft: true,
                updatedAt: .now.addingTimeInterval(-86400 * 3),
                reviewDecision: .changesRequested, checks: .failure
            ),
            PullRequestItem(
                id: "3", number: 1204, title: "Bump dependencies for PHP 8.4",
                repository: "octo/toolkit", author: "dara",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/3?v=4"),
                url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now.addingTimeInterval(-600),
                reviewDecision: .reviewRequired, checks: .pending
            ),
        ]
        notifications = [
            NotificationItem(
                id: "n1", title: "Can you take a look at the migration order?",
                repository: "octo/server",
                avatarURL: URL(string: "https://avatars.githubusercontent.com/u/9919?v=4"),
                reason: .mention,
                updatedAt: .now.addingTimeInterval(-1800),
                subjectType: "Issue",
                latestCommentAPIURL: URL(string: "https://api.github.com/repos/octo/server/issues/comments/1"),
                subjectAPIURL: URL(string: "https://api.github.com/repos/octo/server/issues/42")
            ),
            NotificationItem(
                id: "n2", title: "Release 8.2 checklist",
                repository: "octo/toolkit",
                avatarURL: URL(string: "https://avatars.githubusercontent.com/u/6154722?v=4"),
                reason: .teamMention,
                updatedAt: .now.addingTimeInterval(-7200),
                subjectType: "Issue", latestCommentAPIURL: nil,
                subjectAPIURL: URL(string: "https://api.github.com/repos/octo/toolkit/pulls/1204")
            ),
        ]
        // Show one preview open, so the expanded layout is exercised too.
        previews["n1"] = .text(
            """
            I think the migration for the session table has to run before the \
            index is added, otherwise the unique constraint fails on existing \
            rows. Could you check the ordering?
            """
        )
        expandedNotificationID = "n1"
        loadState = .loaded(.now)
    }
}
