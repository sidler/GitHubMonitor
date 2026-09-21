import Foundation
import Observation

public enum MainWindowTab: String, Hashable, CaseIterable, Sendable {
    case pullRequests
    case myPullRequests
    case mentions
    case dashboard
    case settings

    public var label: String {
        switch self {
        case .pullRequests: "Reviews Requested"
        case .myPullRequests: "My Pull Requests"
        case .mentions: "Mentions"
        case .dashboard: "Dashboard"
        case .settings: "Settings"
        }
    }

    public var symbolName: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .myPullRequests: "person.crop.circle"
        case .mentions: "bell"
        case .dashboard: "chart.bar"
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
    /// Pull requests the user opened, still waiting on other people.
    public var authoredPullRequests: [PullRequestItem] = []
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
    /// The notification whose message is open: in the window's detail pane,
    /// and inline in the popover, which has nowhere else to put it.
    public var expandedNotificationID: String?
    /// The pull request shown in the detail pane, if it is open.
    public var inspectedPullRequestID: String?
    /// Detail payloads, fetched per pull request when its pane is opened.
    public var pullRequestDetails: [String: DetailState] = [:]
    public var sidebarSelection: SidebarSelection = .pullRequests(repository: nil)
    public var selectedSettingsTab: SettingsTab = .account
    /// The dashboard's own fetch, separate from the refresh cycle: it covers
    /// a whole repository and is only wanted while that view is open.
    public var dashboard: DashboardState = .unconfigured
    /// Whether the content column is scrolled away from its top. The title
    /// bar band only needs a material once rows are passing behind it.
    public var isContentScrolled = false

    public init(settings: Settings) {
        self.settings = settings
    }

    /// Pull requests after every filter -- what the list shows and what the
    /// menu bar counts. Both read this so they cannot drift apart.
    public var visiblePullRequests: [PullRequestItem] {
        sorted(PullRequestFilter.apply(
            pullRequests,
            includeDrafts: settings.includeDrafts,
            repositoryFilters: settings.repositoryFilters
        ))
    }

    /// Newest first, on whichever date the user picked.
    ///
    /// Sorted here rather than in the parser so switching the order is
    /// instant: the data is already in hand, and a refetch to reverse a list
    /// would spend a request on something arithmetic.
    private func sorted(_ items: [PullRequestItem]) -> [PullRequestItem] {
        let sort = settings.pullRequestSort
        return items.sorted { lhs, rhs in
            let left = lhs.date(for: sort)
            let right = rhs.date(for: sort)
            // Timestamps do collide -- a batch opened by a bot shares a
            // second. Falling back to the id keeps rows from swapping places
            // on every refresh.
            return left == right ? lhs.id > rhs.id : left > right
        }
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

    /// The user's own pull requests, after the same filters.
    public var visibleAuthoredPullRequests: [PullRequestItem] {
        sorted(PullRequestFilter.apply(
            authoredPullRequests,
            includeDrafts: settings.includeDrafts,
            repositoryFilters: settings.repositoryFilters
        ))
    }

    public var selectedAuthoredPullRequests: [PullRequestItem] {
        narrow(visibleAuthoredPullRequests, to: sidebarSelection.repository, by: \.repository)
    }

    public var authoredRepositories: [SidebarRepository] {
        RepositoryGrouping.group(visibleAuthoredPullRequests, by: \.repository)
            .map { SidebarRepository(repository: $0.repository, count: $0.items.count) }
    }

    /// Drafts in the review queue, whether or not they are shown. Drives the
    /// wording of the popover's draft toggle, which shows that one list.
    public var draftCount: Int { draftCount(in: pullRequests, repository: nil) }

    /// Drafts in the list on screen, whether or not they are shown.
    ///
    /// The main window's toggle sits in that list's own toolbar, so it has to
    /// count that list's drafts: offering to show the review queue's eight
    /// drafts while "My Pull Requests" is open names a number nothing on
    /// screen can account for.
    public var selectedDraftCount: Int {
        switch sidebarSelection {
        case .pullRequests(let repository):
            draftCount(in: pullRequests, repository: repository)
        case .myPullRequests(let repository):
            draftCount(in: authoredPullRequests, repository: repository)
        case .mentions, .dashboard, .settings:
            0
        }
    }

    private func draftCount(in items: [PullRequestItem], repository: String?) -> Int {
        narrow(
            PullRequestFilter.matchingRepositories(items, repositoryFilters: settings.repositoryFilters),
            to: repository,
            by: \.repository
        )
        .count { $0.isDraft }
    }

    /// The list currently shown, narrowed to the selected repository.
    public var selectedPullRequests: [PullRequestItem] {
        narrow(visiblePullRequests, to: sidebarSelection.repository, by: \.repository)
    }

    /// The rows the detail pane can move between: whichever pull request
    /// list is on screen, in the order it is showing them.
    ///
    /// Grouped lists are flattened in the order their sections appear. The
    /// list's own arrow keys walk what is drawn, and a menu item that walked
    /// a different order would send the pane somewhere else on screen.
    public var inspectableItems: [PullRequestItem] {
        let items: [PullRequestItem] =
            switch sidebarSelection {
            case .pullRequests: selectedPullRequests
            case .myPullRequests: selectedAuthoredPullRequests
            case .mentions, .dashboard, .settings: []
            }

        guard settings.listGrouping == .byRepository else { return items }
        return RepositoryGrouping.group(items, by: \.repository).flatMap(\.items)
    }

    public var selectedNotifications: [NotificationItem] {
        narrow(visibleNotifications, to: sidebarSelection.repository, by: \.repository)
    }

    private func narrow<Item>(
        _ items: [Item],
        to repository: String?,
        by key: (Item) -> String
    ) -> [Item] {
        guard let repository else { return items }
        return items.filter { key($0) == repository }
    }

    /// Repository entries under each sidebar heading, busiest first.
    public var pullRequestRepositories: [SidebarRepository] {
        RepositoryGrouping.group(visiblePullRequests, by: \.repository)
            .map { SidebarRepository(repository: $0.repository, count: $0.items.count) }
    }

    public var notificationRepositories: [SidebarRepository] {
        RepositoryGrouping.group(visibleNotifications, by: \.repository)
            .map { SidebarRepository(repository: $0.repository, count: $0.items.count) }
    }

    /// The notification the detail pane is describing, if it is still
    /// unread -- marking it read, here or on GitHub, drops it.
    public var inspectedNotification: NotificationItem? {
        guard let id = expandedNotificationID else { return nil }
        return notifications.first { $0.id == id }
    }

    /// Whether the detail pane has anything to show for the list on screen.
    ///
    /// Tied to the sidebar rather than to whichever id happens to be set:
    /// the pane describes a row in the list being looked at, and a pull
    /// request opened earlier is not that.
    public var hasInspectorContent: Bool {
        switch sidebarSelection {
        case .pullRequests, .myPullRequests: inspectedPullRequest != nil
        case .mentions: inspectedNotification != nil
        case .dashboard, .settings: false
        }
    }

    /// The notifications the detail pane can move between, in the order the
    /// list is showing them.
    public var inspectableNotifications: [NotificationItem] {
        guard case .mentions = sidebarSelection else { return [] }
        switch settings.notificationGrouping {
        case .flat:
            return selectedNotifications
        case .byRepository:
            return RepositoryGrouping.group(selectedNotifications, by: \.repository).flatMap(\.items)
        case .byType:
            return RepositoryGrouping.group(selectedNotifications, by: \.subjectTypeLabel).flatMap(\.items)
        }
    }

    /// The pull request the detail pane is describing, if it is still in the
    /// list -- a refresh can drop it.
    public var inspectedPullRequest: PullRequestItem? {
        guard let id = inspectedPullRequestID else { return nil }
        return (pullRequests + authoredPullRequests).first { $0.id == id }
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
