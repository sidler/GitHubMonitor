import Foundation
import Observation

public enum MainWindowTab: String, Hashable, CaseIterable, Sendable {
    case pullRequests
    case myPullRequests
    case myIssues
    case mentions
    case dashboard
    case trends
    case myTrends
    case settings

    public var label: String {
        switch self {
        case .pullRequests: "Reviews Requested"
        case .myPullRequests: "My Pull Requests"
        case .myIssues: "My Issues"
        case .mentions: "Mentions"
        case .dashboard: "Workload"
        case .trends: "Trends"
        case .myTrends: "My Trends"
        case .settings: "Settings"
        }
    }

    public var symbolName: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .myPullRequests: "person.crop.circle"
        case .myIssues: "smallcircle.filled.circle"
        case .mentions: "bell"
        case .dashboard: "chart.bar"
        case .trends: "chart.xyaxis.line"
        case .myTrends: "person.crop.circle.badge.clock"
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
    /// Issues assigned to the user, from the same refresh as the lists above.
    public var issues: [IssueItem] = []
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
    /// The issue shown in the detail pane, if it is open.
    public var inspectedIssueID: String?
    /// Issue bodies and threads, fetched per issue when its pane is opened.
    public var issueDetails: [String: IssueDetailState] = [:]
    /// Detail payloads, fetched per pull request when its pane is opened.
    public var pullRequestDetails: [String: DetailState] = [:]
    public var sidebarSelection: SidebarSelection = .pullRequests(repository: nil)
    public var selectedSettingsTab: SettingsTab = .account
    /// The dashboard's own fetch, separate from the refresh cycle: it covers
    /// a whole repository and is only wanted while that view is open.
    public var dashboard: DashboardState = .unconfigured
    /// The trend charts, which have their own fetch again: a year of
    /// history is far too expensive to hang off the refresh timer.
    public var trends: TrendState = .unconfigured
    /// The same, for one's own pull requests rather than a repository's.
    public var myTrends: MyTrendState = .unconfigured
    /// Who comments across a whole repository -- read only while that side
    /// of the switch is showing, since it covers every pull request in it.
    public var repositoryCommenters: CommenterState = .unconfigured
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
    private func sorted<Item: ListedItem>(_ items: [Item]) -> [Item] {
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

    /// The issues assigned to the user, after the repository filter and in
    /// the order chosen for the lists. There is no draft toggle here -- an
    /// issue has no draft state.
    public var visibleIssues: [IssueItem] {
        sorted(PullRequestFilter.matchingRepositories(
            issues,
            repositoryFilters: settings.repositoryFilters
        ))
    }

    public var selectedIssues: [IssueItem] {
        narrow(visibleIssues, to: sidebarSelection.repository, by: \.repository)
    }

    public var issueRepositories: [SidebarRepository] {
        RepositoryGrouping.group(visibleIssues, by: \.repository)
            .map { SidebarRepository(repository: $0.repository, count: $0.items.count) }
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
        case .myIssues, .mentions, .dashboard, .trends, .myTrends, .settings:
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
            case .myIssues, .mentions, .dashboard, .trends, .myTrends, .settings: []
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
        case .myIssues: inspectedIssue != nil
        case .mentions: inspectedNotification != nil
        case .dashboard, .trends, .myTrends, .settings: false
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

    /// The issue the detail pane is describing, if it is still assigned --
    /// a refresh drops the ones that were closed or handed on.
    public var inspectedIssue: IssueItem? {
        guard let id = inspectedIssueID else { return nil }
        return issues.first { $0.id == id }
    }

    /// The issues the detail pane can move between, in the order the list is
    /// showing them.
    public var inspectableIssues: [IssueItem] {
        guard case .myIssues = sidebarSelection else { return [] }
        guard settings.listGrouping == .byRepository else { return selectedIssues }
        return RepositoryGrouping.group(selectedIssues, by: \.repository).flatMap(\.items)
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
        issues = [
            IssueItem(
                id: "i1", number: 318, title: "Session table migration order is ambiguous",
                repository: "octo/server", author: "mira",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4"),
                url: URL(string: "https://github.com")!,
                createdAt: .now.addingTimeInterval(-86400 * 9),
                updatedAt: .now.addingTimeInterval(-5400),
                comments: 7,
                labels: [
                    IssueLabel(name: "bug", color: "d73a4a"),
                    IssueLabel(name: "needs decision", color: "fbca04"),
                ],
                milestone: "8.3"
            ),
            IssueItem(
                id: "i2", number: 91, title: "Document the release checklist",
                repository: "octo/website", author: "arun",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/2?v=4"),
                url: URL(string: "https://github.com")!,
                createdAt: .now.addingTimeInterval(-86400 * 30),
                updatedAt: .now.addingTimeInterval(-86400 * 2),
                labels: [IssueLabel(name: "documentation", color: "0075ca")]
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
        // Written as the real ones are -- a bot's table, a details wrapper,
        // a code fence -- so the Markdown rendering is exercised as well.
        previews["n1"] = .loaded(
            CommentPreview(
                author: CommentAuthor(
                    login: "mira",
                    avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4")
                ),
                body: """
            I think the migration for the session table has to run **before** the
            index is added, otherwise the unique constraint fails on existing rows.

            | Step | Migration | Note |
            |---|---|---|
            | 1 | `Migration20260901120000` | adds the column |
            | 2 | `Migration20260901123000` | backfills it |

            ---

            ### What I ran

            ```sh
            bin/console migration:run --dry-run
            ```

            - the dry run is clean
            - the index still fails on row 4711

            > Could you check the ordering?
            """
            )
        )
        expandedNotificationID = "n1"
        loadState = .loaded(.now)
    }
}
