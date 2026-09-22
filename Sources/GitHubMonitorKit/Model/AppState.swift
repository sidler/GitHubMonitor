import Foundation
import Observation

/// A view the window can be opened on, for the menu bar's entry points and
/// the development hooks.
///
/// A list is named rather than enumerated now that lists are made by the
/// user: anything that is not one of the fixed views is taken as a list's id
/// or title.
public enum MainWindowTab: Hashable, Sendable {
    case list(String)
    case mentions
    case dashboard
    case trends
    case myTrends
    case settings

    public init(name: String) {
        switch name {
        case "mentions": self = .mentions
        case "dashboard": self = .dashboard
        case "trends": self = .trends
        case "myTrends": self = .myTrends
        case "settings": self = .settings
        default: self = .list(name)
        }
    }
}

public enum SettingsTab: String, Hashable, CaseIterable, Sendable {
    case account
    case lists
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

    /// What each list brought back, keyed by the list's id.
    ///
    /// Two dictionaries rather than one of a mixed type: a list shows one
    /// kind of thing, and every view that reads these already knows which.
    public var listPullRequests: [String: [PullRequestItem]] = [:]
    public var listIssues: [String: [IssueItem]] = [:]
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
    /// Set to whatever the first visible list is at launch; the fallback
    /// only matters until `normaliseSelection()` runs in `init`.
    public var sidebarSelection: SidebarSelection = .dashboard
    public var selectedSettingsTab: SettingsTab = .account
    /// The dashboard's own fetch, separate from the refresh cycle: it covers
    /// a whole repository and is only wanted while that view is open.
    public var dashboard: DashboardState = .unconfigured
    /// The bar of the workload chart whose pull requests are being listed.
    public var workloadSelection: WorkloadSelection?
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
        // Start on the first list that is shown in the window; the stored
        // default cannot know which lists exist, and starting on one that is
        // not in the sidebar would show a view with no way back to it.
        if let first = settings.savedLists.first(where: {
            settings.listVisibility.isShown($0.id, in: .window)
        }) {
            sidebarSelection = .list(id: first.id, repository: nil)
        }
        normaliseSelection()
    }

    // MARK: - Lists

    public var lists: [SavedList] { settings.savedLists }

    public func list(withID id: String) -> SavedList? { settings.list(withID: id) }

    /// The list the sidebar is pointing at, if it is pointing at one.
    public var selectedList: SavedList? {
        guard let id = sidebarSelection.listID else { return nil }
        return list(withID: id)
    }

    /// One list's rows, after the filters that are applied here rather than
    /// in the search: drafts, which the toggle has to hide without a round
    /// trip, and the issue types switched off for that list.
    public func pullRequests(in list: SavedList) -> [PullRequestItem] {
        let items = listPullRequests[list.id] ?? []
        let shown = settings.includeDrafts ? items : items.filter { !$0.isDraft }
        return sorted(shown, by: list.sort)
    }

    public func issues(in list: SavedList) -> [IssueItem] {
        IssueFilter.sorted(
            (listIssues[list.id] ?? []).filter { !list.hiddenTypes.contains($0.typeName) },
            by: list.sort
        )
    }

    /// What the sidebar, the status bar and the menu bar all count for one
    /// list. One definition, so they cannot drift apart.
    public func count(of list: SavedList) -> Int {
        switch list.content {
        case .pullRequests: pullRequests(in: list).count
        case .issues: issues(in: list).count
        }
    }

    /// Newest first, on whichever date the list is ordered by.
    ///
    /// Sorted here rather than in the parser so switching the order is
    /// instant: the data is already in hand, and a refetch to reverse a list
    /// would spend a request on something arithmetic.
    private func sorted(_ items: [PullRequestItem], by sort: ListSort) -> [PullRequestItem] {
        items.sorted { lhs, rhs in
            let left = lhs.date(for: sort.date)
            let right = rhs.date(for: sort.date)
            // Timestamps do collide -- a batch opened by a bot shares a
            // second. Falling back to the id keeps rows from swapping places
            // on every refresh.
            return left == right ? lhs.id > rhs.id : left > right
        }
    }

    /// The same, narrowed to the repository the sidebar points at.
    public func selectedPullRequests(in list: SavedList) -> [PullRequestItem] {
        narrow(pullRequests(in: list), to: sidebarSelection.repository, by: \.repository)
    }

    public func selectedIssues(in list: SavedList) -> [IssueItem] {
        narrow(issues(in: list), to: sidebarSelection.repository, by: \.repository)
    }

    /// The repository entries under a list in the sidebar, busiest first.
    public func repositories(in list: SavedList) -> [SidebarRepository] {
        let repositories: [String]
        switch list.content {
        case .pullRequests: repositories = pullRequests(in: list).map(\.repository)
        case .issues: repositories = issues(in: list).map(\.repository)
        }
        return RepositoryGrouping.group(repositories, by: { $0 })
            .map { SidebarRepository(repository: $0.repository, count: $0.items.count) }
    }

    /// Everything every list holds, for the places that are about the data
    /// rather than about one list: the repository suggestions in settings
    /// and in the workload chart.
    public var allPullRequests: [PullRequestItem] {
        var seen = Set<String>()
        return listPullRequests.values.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    public var allIssues: [IssueItem] {
        var seen = Set<String>()
        return listIssues.values.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    /// What the window's title bar says: the repository when one is chosen,
    /// the list or section otherwise.
    public var selectionTitle: String {
        if let repository = sidebarSelection.repository { return repository }
        if let list = selectedList { return list.title }
        return sidebarSelection.fixedTitle ?? ""
    }

    /// The line under it, so a repository selection still says what it is
    /// showing.
    public var selectionSubtitle: String {
        guard sidebarSelection.repository != nil else { return "" }
        if let list = selectedList { return list.title }
        return sidebarSelection.fixedSubtitle ?? ""
    }

    // MARK: - Counts per surface

    /// The lists one surface shows, with their counts, in sidebar order and
    /// with the mentions last.
    public func counts(in surface: DisplaySurface) -> [SurfaceCount] {
        var result = lists
            .filter { settings.listVisibility.isShown($0.id, in: surface) }
            .map { SurfaceCount(id: $0.id, title: $0.title, symbolName: $0.symbol, count: count(of: $0)) }

        if settings.listVisibility.isShown(ListVisibility.mentionsKey, in: surface) {
            result.append(
                SurfaceCount(
                    id: ListVisibility.mentionsKey,
                    title: "Mentions",
                    symbolName: StatusBarTitleBuilder.mentionSymbol,
                    count: visibleNotifications.count
                )
            )
        }
        return result
    }

    /// Moves the sidebar off a list that is not shown in the window, or off
    /// one that has been deleted.
    ///
    /// Called when the lists or the switches change and at launch: the
    /// content column follows this selection, so a list that is not in the
    /// sidebar would still be on screen with no entry to leave it by.
    public func normaliseSelection() {
        switch sidebarSelection {
        case .list(let id, _):
            guard
                list(withID: id) == nil
                    || !settings.listVisibility.isShown(id, in: .window)
            else { return }
        case .mentions:
            guard !settings.listVisibility.isShown(ListVisibility.mentionsKey, in: .window) else {
                return
            }
        case .dashboard, .trends, .myTrends, .settings:
            return
        }

        if let first = lists.first(where: { settings.listVisibility.isShown($0.id, in: .window) }) {
            sidebarSelection = .list(id: first.id, repository: nil)
        } else if settings.listVisibility.isShown(ListVisibility.mentionsKey, in: .window) {
            sidebarSelection = .mentions(repository: nil)
        } else {
            // Nothing left to list; the window still has its other views.
            sidebarSelection = .dashboard
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

    public var notificationRepositories: [SidebarRepository] {
        RepositoryGrouping.group(visibleNotifications, by: \.repository)
            .map { SidebarRepository(repository: $0.repository, count: $0.items.count) }
    }

    // MARK: - The list on screen

    /// Drafts in the list on screen, whether or not they are shown.
    ///
    /// The toggle sits in that list's own toolbar, so it has to count that
    /// list's drafts: offering to show another list's eight drafts names a
    /// number nothing on screen can account for.
    public var selectedDraftCount: Int {
        guard let list = selectedList, list.content == .pullRequests else { return 0 }
        return narrow(
            listPullRequests[list.id] ?? [],
            to: sidebarSelection.repository,
            by: \.repository
        )
        .count { $0.isDraft }
    }

    /// The types on offer in the filter of the list on screen, counted
    /// before that filter is applied -- a type switched off has to stay in
    /// the menu, or there is no way to switch it back on.
    public var selectedTypeTallies: [IssueTypeTally] {
        guard let list = selectedList, list.content == .issues else { return [] }
        return IssueFilter.tallies(of: listIssues[list.id] ?? [])
    }

    /// How many rows the type filter is leaving out, for the toolbar to say
    /// so rather than leaving an unexplained gap between the counts.
    public var hiddenIssueCount: Int {
        guard let list = selectedList, list.content == .issues else { return 0 }
        return (listIssues[list.id] ?? []).count - issues(in: list).count
    }

    /// The rows the detail pane can move between: the list on screen, in the
    /// order it is showing them.
    ///
    /// Grouped lists are flattened in the order their sections appear. The
    /// list's own arrow keys walk what is drawn, and a menu item that walked
    /// a different order would send the pane somewhere else on screen.
    public var inspectableItems: [PullRequestItem] {
        guard let list = selectedList, list.content == .pullRequests else { return [] }
        let items = selectedPullRequests(in: list)
        guard list.grouping == .byRepository else { return items }
        return RepositoryGrouping.group(items, by: \.repository).flatMap(\.items)
    }

    public var inspectableIssues: [IssueItem] {
        guard let list = selectedList, list.content == .issues else { return [] }
        let items = selectedIssues(in: list)
        switch list.grouping {
        case .flat: return items
        case .byRepository:
            return RepositoryGrouping.group(items, by: \.repository).flatMap(\.items)
        case .byType:
            return RepositoryGrouping.group(items, by: \.typeName).flatMap(\.items)
        }
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
        case .list(let id, _):
            switch list(withID: id)?.content {
            case .pullRequests: inspectedPullRequest != nil
            case .issues: inspectedIssue != nil
            case nil: false
            }
        case .mentions: inspectedNotification != nil
        case .dashboard: inspectedWorkload != nil
        case .trends, .myTrends, .settings: false
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
        return allPullRequests.first { $0.id == id }
    }

    /// The issue the detail pane is describing, if it is still assigned --
    /// a refresh drops the ones that were closed or handed on.
    public var inspectedIssue: IssueItem? {
        guard let id = inspectedIssueID else { return nil }
        return allIssues.first { $0.id == id }
    }

    /// The pull requests behind the bar that was clicked in the workload
    /// chart, if that bar is still in the chart.
    ///
    /// Resolved against the data on screen rather than remembered: a reload
    /// can drop a person entirely, and a pane describing somebody the chart
    /// no longer shows would be describing nothing.
    public var inspectedWorkload: WorkloadDetail? {
        guard
            case .dashboard = sidebarSelection,
            let selection = workloadSelection,
            selection.grouping == settings.dashboardGrouping,
            case .loaded(let data) = dashboard
        else { return nil }

        switch selection.grouping {
        case .author:
            return data.authors.first { $0.id == selection.id }.map(WorkloadDetail.init)
        case .reviewer:
            return data.reviewers.first { $0.id == selection.id }.map(WorkloadDetail.init)
        }
    }

    /// The bars the detail pane can move between, top to bottom.
    public var inspectableWorkload: [WorkloadSelection] {
        guard case .dashboard = sidebarSelection, case .loaded(let data) = dashboard else {
            return []
        }
        let grouping = settings.dashboardGrouping
        switch grouping {
        case .author:
            return data.authors.map { WorkloadSelection(grouping: grouping, id: $0.id) }
        case .reviewer:
            return data.reviewers.map { WorkloadSelection(grouping: grouping, id: $0.id) }
        }
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
        listPullRequests[SavedList.Seed.reviews] = [
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
        listIssues[SavedList.Seed.issues] = [
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
