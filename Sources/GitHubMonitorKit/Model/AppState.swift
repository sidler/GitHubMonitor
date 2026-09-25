import Foundation
import CoreGraphics
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

/// A pull request's diff, open over the window.
///
/// In the app's state rather than the pane's, because the overlay is put up
/// by the window itself: the pane is 400 points wide and an overlay inside
/// it could never be anything else.
public struct OpenedDiff: Equatable, Sendable {
    public let pullRequestID: String
    /// The file at the top of the overlay. Written both by scrolling it and
    /// by the list beside it, which is what makes the two follow each other.
    public var path: String?
    /// The diff itself, taken when it was opened.
    ///
    /// Carried here rather than read from `changedFiles` as it goes: that
    /// dictionary is rebuilt by every refresh, and a refresh arriving while
    /// someone reads a diff would take the diff away from under them. What
    /// is on screen is one diff at one commit, and it stays that until it
    /// is closed -- the same reason the approval is bound to a commit.
    public let files: [ChangedFile]
    /// Kept here for the same reason: the links in the overlay must still
    /// work for a pull request that has left the lists while it was open.
    public let url: URL

    public init(pullRequestID: String, path: String?, files: [ChangedFile], url: URL) {
        self.pullRequestID = pullRequestID
        self.path = path
        self.files = files
        self.url = url
    }
}

/// An approval, from the click to whatever GitHub answered.
public enum ApprovalState: Equatable, Sendable {
    case idle
    /// Looking at the head commit, before anything is written.
    case checking(pullRequestID: String)
    /// The check passed and the question is on screen.
    ///
    /// Part of the app's state rather than the overlay's: every step here
    /// rebuilds the overlay, and a question that lived inside it was thrown
    /// away by the very change that was supposed to raise it.
    case confirming(pullRequestID: String)
    /// Waiting for the mutation.
    case sending(pullRequestID: String)
    /// Refused before it was sent, or rejected by GitHub. Either way
    /// nothing was written.
    case failed(pullRequestID: String, message: String)

    public var pullRequestID: String? {
        switch self {
        case .idle: nil
        case .checking(let id), .confirming(let id), .sending(let id): id
        case .failed(let id, _): id
        }
    }

    public var isBusy: Bool {
        switch self {
        case .checking, .sending: true
        case .idle, .confirming, .failed: false
        }
    }

    public func isConfirming(_ pullRequestID: String) -> Bool {
        if case .confirming(let id) = self { return id == pullRequestID }
        return false
    }

    public func message(for pullRequestID: String) -> String? {
        guard case .failed(let id, let message) = self, id == pullRequestID else { return nil }
        return message
    }
}

public enum LoadState: Equatable, Sendable {
    case idle
    /// Refreshing has stopped until GitHub restores the allowance.
    case paused(until: Date?)
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
    /// Comment bodies, fetched only when a row is opened.
    public var previews: [String: PreviewState] = [:]
    /// The conversation behind a notification, fetched when its pane opens.
    /// A mention lives in a comment, so the pane needs more than the one
    /// message the notification points at.
    public var notificationThreads: [String: IssueDetailState] = [:]
    /// The notification expanded inline in the popover, which has nowhere
    /// else to put a message.
    ///
    /// Separate from the window's, so opening one in the popover does not
    /// open a detail pane in a window behind it -- and closing it there does
    /// not close what is being read here.
    public var expandedNotificationID: String?
    /// The notification the window's detail pane is describing.
    public var inspectedNotificationID: String?
    /// The pull request shown in the detail pane, if it is open.
    public var inspectedPullRequestID: String?
    /// The issue shown in the detail pane, if it is open.
    public var inspectedIssueID: String?
    /// Issue bodies and threads, fetched per issue when its pane is opened.
    public var issueDetails: [String: IssueDetailState] = [:]
    /// Detail payloads, fetched per pull request when its pane is opened.
    public var pullRequestDetails: [String: DetailState] = [:]
    /// The files each opened pull request touches. Kept beside the detail
    /// rather than inside it: it is a second request, to a different API,
    /// and one arriving should not wait on the other.
    public var changedFiles: [String: ChangedFilesState] = [:]
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
    /// How many searches a refresh runs: one per line of every list that is
    /// shown somewhere. What the cost of keeping up to date is measured in.
    public var runningSearchCount: Int {
        settings.savedLists
            .filter { $0.isRunnable && settings.listVisibility.isShownAnywhere($0.id) }
            .reduce(0) { $0 + $1.queryLines.count }
    }

    /// How many rows each list is not showing, where paging was cut short.
    /// Empty for every list that was read to the end, which is nearly all
    /// of them.
    public var listUnread: [String: Int] = [:]

    /// Where an approval stands, for the one pull request being approved.
    public var approval: ApprovalState = .idle

    /// The diff being read over the window, if any.
    public var openedDiff: OpenedDiff?

    /// What is left of GitHub's two hourly allowances, as last reported.
    public var budgets = RateBudgets()
    /// Whether the content column is scrolled away from its top. The title
    /// bar band only needs a material once rows are passing behind it.
    public var isContentScrolled = false
    /// Whether the sidebar is collapsed. The content column draws the window
    /// title, and when the sidebar goes the traffic lights land where that
    /// title starts.
    public var isSidebarCollapsed = false
    /// How wide the toolbar's own controls are, so a long title truncates
    /// before it runs under them rather than behind them.
    public var toolbarControlsWidth: CGFloat = 0

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
        let shown = list.includeDrafts ? items : items.filter { !$0.isDraft }
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
    /// How many a list is not showing, because it ran past what the app
    /// will page through. Zero for every list that fits.
    public func unshown(in list: SavedList) -> Int {
        listUnread[list.id] ?? 0
    }

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
        guard sort != .waiting else { return byWaiting(items) }
        return items.sorted { lhs, rhs in
            let left = lhs.date(for: sort.date)
            let right = rhs.date(for: sort.date)
            // Timestamps do collide -- a batch opened by a bot shares a
            // second. Falling back to the id keeps rows from swapping places
            // on every refresh.
            return left == right ? lhs.id > rhs.id : left > right
        }
    }

    /// Longest-waiting first, and everything nobody asked of you after it.
    ///
    /// The tail keeps its usual order rather than being dropped: a list is
    /// still a list of what it searched for, and a pull request with no
    /// request naming this person -- their own, or one asked of a team --
    /// has no place in the ordering the sort is about.
    private func byWaiting(_ items: [PullRequestItem]) -> [PullRequestItem] {
        let waiting = items
            .filter { $0.reviewRequestedAt != nil }
            .sorted { lhs, rhs in
                let left = lhs.reviewRequestedAt!
                let right = rhs.reviewRequestedAt!
                return left == right ? lhs.id > rhs.id : left < right
            }
        let rest = sorted(items.filter { $0.reviewRequestedAt == nil }, by: .updated)
        return waiting + rest
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

    /// One pull request by id, wherever it was fetched into. The file list
    /// is asked for by repository and number, which only the item carries.
    public func pullRequest(withID id: String) -> PullRequestItem? {
        allPullRequests.first { $0.id == id }
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
        if sidebarSelection.isMentions { return settings.mentionsTitle }
        return sidebarSelection.fixedTitle ?? ""
    }

    /// The line under it, so a repository selection still says what it is
    /// showing.
    public var selectionSubtitle: String {
        guard sidebarSelection.repository != nil else { return "" }
        if let list = selectedList { return list.title }
        if sidebarSelection.isMentions { return settings.mentionsTitle }
        return sidebarSelection.fixedSubtitle ?? ""
    }

    // MARK: - Counts per surface

    /// What one surface shows, with their counts, in sidebar order.
    public func counts(in surface: DisplaySurface) -> [SurfaceCount] {
        settings.entries
            .filter { settings.listVisibility.isShown($0.id, in: surface) }
            .map { entry in
                switch entry {
                case .list(let list):
                    SurfaceCount(
                        id: list.id, title: list.title,
                        symbolName: list.symbol, count: count(of: list)
                    )
                case .mentions:
                    SurfaceCount(
                        id: ListVisibility.mentionsKey, title: settings.mentionsTitle,
                        symbolName: settings.mentionsSymbol, count: visibleNotifications.count
                    )
                }
            }
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
        guard let id = inspectedNotificationID else { return nil }
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
        case .paused(let until):
            if let until {
                "Paused \u{2014} GitHub's budget resets at \(RelativeTime.clock(until))"
            } else {
                "Paused \u{2014} GitHub's hourly budget is spent"
            }
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
                reviewDecision: .reviewRequired, checks: .success,
                mergeStatus: .conflicting,
                headCommit: "22da5a177503201b9cbbe78802da6353299f74df",
                isAutoMergeArmed: true,
                // Long enough to be called overdue under any sane threshold.
                reviewRequestedAt: .now.addingTimeInterval(-86400 * 9)
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
                reviewDecision: .reviewRequired, checks: .pending,
                mergeStatus: .mergeable,
                reviewRequestedAt: .now.addingTimeInterval(-86400 * 4)
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
        // One detail pane filled in, so the section that reports whether a
        // pull request still merges is exercised without a token.
        pullRequestDetails["1"] = .loaded(
            PullRequestDetail(
                headBranch: "fix/session-handler-race",
                baseBranch: "main",
                additions: 154, deletions: 64, changedFiles: 6, comments: 4,
                mergeStatus: .conflicting,
                checks: [
                    CheckRun(name: "phpunit", status: .success),
                    CheckRun(name: "phpstan", status: .success),
                ],
                reviewers: [
                    ReviewerStatus(name: "arun", avatarURL: nil, state: .pending, isTeam: false),
                ]
            )
        )
        // One small patch, shown without asking, and one large enough to
        // stay folded -- both sides of the rule the pane follows.
        changedFiles["1"] = .loaded([
            ChangedFile(
                path: "core/module_system/src/Session/SessionHandler.php",
                additions: 6, deletions: 2, change: .modified,
                patch: """
                @@ -118,8 +118,12 @@ class SessionHandler implements SessionHandlerInterface
                     public function write(string $id, string $data): bool
                     {
                -        $this->connection->insert(self::TABLE, ['id' => $id]);
                -        return true;
                +        // The unique index fails on rows written before 8.3.
                +        if ($this->connection->has(self::TABLE, $id)) {
                +            return $this->connection->update(self::TABLE, ['data' => $data]);
                +        }
                +
                +        return $this->connection->insert(self::TABLE, ['id' => $id, 'data' => $data]);
                     }
                """
            ),
            ChangedFile(
                path: "core/module_system/config/migrations.yml",
                additions: 2, deletions: 0, change: .modified,
                patch: "@@ -4,2 +4,4 @@\n order:\n   - Migration20260901120000\n+  - Migration20260901123000\n+  # runs after the column exists\n"
            ),
            ChangedFile(
                path: "core/module_system/src/Filter/SessionFilter.php",
                additions: 3, deletions: 1, change: .modified,
                patch: "@@ -12,3 +12,5 @@\n class SessionFilter\n-    public $id;\n+    public string $id = '';\n+    public string $data = '';\n"
            ),
            ChangedFile(
                path: "core/module_system/src/Filter/UserFilter.php",
                additions: 1, deletions: 1, change: .modified,
                patch: "@@ -8,1 +8,1 @@\n-#[ModuleId('_system_module_id_')]\n+#[ModuleId(_system_module_id_)]\n"
            ),
            ChangedFile(
                path: "README.md",
                additions: 2, deletions: 0, change: .modified,
                patch: "@@ -1,2 +1,4 @@\n # Core\n+\n+Requires PHP 8.4.\n"
            ),
            ChangedFile(
                path: "core/module_system/tests/SessionHandlerTest.php",
                additions: 140, deletions: 60, change: .modified,
                patch: "@@ -1,200 +1,280 @@\n" + Array(repeating: "+        $this->assertTrue(true);", count: 40).joined(separator: "\n")
            ),
        ])
        pullRequestDetails["3"] = .loaded(
            PullRequestDetail(
                headBranch: "chore/php-8.4",
                baseBranch: "main",
                additions: 812, deletions: 806, changedFiles: 21, comments: 0,
                mergeStatus: .mergeable,
                checks: [CheckRun(name: "composer-audit", status: .pending)],
                reviewers: []
            )
        )
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

            ```php
            // the order the runner picked
            $runner->run(['Migration20260901120000', 'Migration20260901123000']);
            ```

            - the dry run is clean
            - the index still fails on row 4711

            > Could you check the ordering?
            """
            )
        )
        budgets = RateBudgets(
            graphQL: RateBudget(remaining: 4712, limit: 5000, resetAt: .now.addingTimeInterval(1500)),
            rest: RateBudget(remaining: 4871, limit: 5000, resetAt: .now.addingTimeInterval(2100))
        )
        myTrends = .loaded(Self.sampleTrends)
        expandedNotificationID = "n1"
        inspectedNotificationID = "n1"
        loadState = .loaded(.now)
    }

    /// A short history, so the personal charts can be looked at without a
    /// token -- including the one about how long reviews wait on you, which
    /// otherwise only exists once a real year has been fetched.
    private static var sampleTrends: MyTrendData {
        let calendar = Calendar(identifier: .gregorian)
        var buckets: [MyTrendBucket] = []
        let medians: [TimeInterval] = [2.5, 6, 3, 19, 4.5, 2, 8, 1.5].map { $0 * 3600 }

        for (index, median) in medians.enumerated() {
            let start = calendar.date(byAdding: .weekOfYear, value: -(medians.count - index), to: .now)!
            buckets.append(MyTrendBucket(
                start: start,
                end: calendar.date(byAdding: .weekOfYear, value: 1, to: start)!,
                opened: 3 + index % 4,
                hours: [9: 1, 11: 2, 15: 1],
                commentsFromPeople: TrendPoint(median: 3, fastest: 0, slowest: 9, samples: 4),
                commentsFromEveryone: TrendPoint(median: 5, fastest: 1, slowest: 14, samples: 4),
                commentersFromPeople: ["mira": 6, "arun": 3],
                commentersFromEveryone: ["mira": 6, "arun": 3, "renovate": 9],
                merge: TrendPoint(
                    median: median * 6, fastest: median * 2, slowest: median * 18, samples: 5
                ),
                response: TrendPoint(
                    median: median, fastest: median / 6, slowest: median * 9, samples: 7
                )
            ))
        }

        return MyTrendData(login: "sidler", resolution: .weekly, buckets: buckets)
    }
}
