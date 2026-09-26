import Foundation
import Testing
@testable import GitHubMonitorKit

@MainActor
@Suite("Sorting the pull request lists")
struct PullRequestSortTests {
    private let list = SavedList(
        id: "l", title: "A list", query: "is:pr review-requested:@me", content: .pullRequests
    )

    private func makeState() -> AppState {
        let defaults = TestDefaults.make()
        let state = AppState(settings: Settings(store: defaults))
        state.settings.savedLists = [list]
        state.sidebarSelection = .list(id: list.id, repository: nil)
        return state
    }

    /// The order is the list's own now, so changing it means rewriting the
    /// list -- which is what the toolbar's picker does.
    private func order(_ state: AppState, by sort: ListSort) -> [String] {
        var updated = list
        updated.sort = sort
        state.settings.update(updated)
        return state.pullRequests(in: updated).map(\.id)
    }

    /// Opened long ago, touched a minute ago -- and the reverse. Only a list
    /// that reads the right field can tell them apart.
    private func item(
        id: String,
        openedDaysAgo: Int,
        updatedDaysAgo: Int,
        draft: Bool = false
    ) -> PullRequestItem {
        let day: TimeInterval = 86_400
        return PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: draft,
            createdAt: .now.addingTimeInterval(-day * Double(openedDaysAgo)),
            updatedAt: .now.addingTimeInterval(-day * Double(updatedDaysAgo)),
            reviewDecision: .none, checks: .none
        )
    }

    private func loaded() -> AppState {
        let state = makeState()
        state.listPullRequests[list.id] = [
            item(id: "old-but-busy", openedDaysAgo: 30, updatedDaysAgo: 1),
            item(id: "fresh-and-quiet", openedDaysAgo: 2, updatedDaysAgo: 2),
        ]
        return state
    }

    @Test("By default a list follows the last activity")
    func defaultsToUpdated() {
        let state = loaded()
        #expect(list.sort == .updated)
        #expect(order(state, by: .updated) == ["old-but-busy", "fresh-and-quiet"])
    }

    @Test("Sorting by date opened reads the other field")
    func byCreated() {
        let state = loaded()
        #expect(order(state, by: .created) == ["fresh-and-quiet", "old-but-busy"])
    }

    /// Each list carries its own order: one of them being read by date
    /// opened says nothing about the next.
    @Test("The order belongs to the list, not to the app")
    func perList() {
        let state = loaded()
        var other = SavedList(id: "other", title: "Other", query: "is:pr author:@me", content: .pullRequests)
        other.sort = .created
        state.settings.savedLists = [list, other]
        state.listPullRequests[other.id] = state.listPullRequests[list.id]

        #expect(state.pullRequests(in: list).map(\.id) == ["old-but-busy", "fresh-and-quiet"])
        #expect(state.pullRequests(in: other).map(\.id) == ["fresh-and-quiet", "old-but-busy"])
    }

    /// Bots open pull requests in batches that share a timestamp to the
    /// second; without a tiebreak those rows would swap places on every
    /// refresh, under the reader's cursor.
    @Test("Rows with the same timestamp keep a stable order")
    func stableOrder() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        func tied(_ ids: [String]) -> [String] {
            let state = makeState()
            state.listPullRequests[list.id] = ids.map { id in
                PullRequestItem(
                    id: id, number: 1, title: "t", repository: "r", author: "a",
                    authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                    createdAt: moment, updatedAt: moment, reviewDecision: .none, checks: .none
                )
            }
            return state.pullRequests(in: list).map(\.id)
        }
        // The same rows in a different order out of GitHub must still land
        // in the same order on screen.
        #expect(tied(["b", "a", "c"]) == tied(["c", "b", "a"]))
    }

    /// A pull request has always been opened before it was last touched, so
    /// a missing creation date must not sort a row to the top.
    @Test("A payload without a creation date falls back to the activity date")
    func missingCreatedAt() {
        let updated = Date(timeIntervalSince1970: 1_700_000_000)
        let item = PullRequestItem(
            id: "a", number: 1, title: "t", repository: "r", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: updated, reviewDecision: .none, checks: .none
        )
        #expect(item.createdAt == updated)
        #expect(item.date(for: .created) == updated)
    }

    @Test("The choice survives a restart")
    func persisted() {
        let suite = TestDefaults.reserveName()
        let defaults = UserDefaults(suiteName: suite)!
        var stored = list
        stored.sort = .created
        Settings(store: defaults).savedLists = [stored]
        #expect(Settings(store: defaults).savedLists.first?.sort == .created)
    }

    @Test("Both dates are offered, and named")
    func options() {
        #expect(PullRequestSort.allCases == [.updated, .created])
        for sort in PullRequestSort.allCases {
            #expect(!sort.label.isEmpty)
            #expect(!sort.rowPrefix.isEmpty)
        }
    }
}

@MainActor
@Suite("Moving the detail pane by keyboard")
struct InspectionMovementTests {
    private func makeController() -> (AppState, RefreshController) {
        let defaults = TestDefaults.make()
        let state = AppState(settings: Settings(store: defaults))
        let list = SavedList(
            id: "l", title: "A list", query: "is:pr review-requested:@me", content: .pullRequests
        )
        state.settings.savedLists = [list]
        state.sidebarSelection = .list(id: list.id, repository: nil)
        state.listPullRequests[list.id] = (1...3).map { index in
            PullRequestItem(
                id: "\(index)", number: index, title: "t", repository: "r", author: "a",
                authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now.addingTimeInterval(TimeInterval(-60 * index)),
                reviewDecision: .none, checks: .none
            )
        }
        return (state, RefreshController(state: state))
    }

    @Test("With nothing open, moving down starts at the top of the list")
    func startsAtTop() {
        let (state, controller) = makeController()
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == "1")
    }

    @Test("With nothing open, moving up starts at the bottom")
    func startsAtBottom() {
        let (state, controller) = makeController()
        controller.moveInspection(by: -1)
        #expect(state.inspectedPullRequestID == "3")
    }

    @Test("Moving follows the order on screen")
    func moves() {
        let (state, controller) = makeController()
        state.inspectedPullRequestID = "2"
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == "3")
        controller.moveInspection(by: -1)
        #expect(state.inspectedPullRequestID == "2")
    }

    /// Wrapping from the last row to the first loses the reader's place, and
    /// in a queue of thirty rows it is not even visible that it happened.
    @Test("Moving stops at the ends rather than wrapping")
    func stopsAtEnds() {
        let (state, controller) = makeController()
        state.inspectedPullRequestID = "3"
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == "3")

        state.inspectedPullRequestID = "1"
        controller.moveInspection(by: -1)
        #expect(state.inspectedPullRequestID == "1")
    }

    /// The order the keyboard walks has to be the order on screen, or the
    /// pane jumps to a row somewhere else in the list.
    @Test("Re-sorting changes what the next row is")
    func followsTheSort() {
        let (state, controller) = makeController()
        var list = try! #require(state.lists.first)
        list.sort = .created
        state.settings.update(list)
        state.listPullRequests[list.id] = [
            PullRequestItem(
                id: "old", number: 1, title: "t", repository: "r", author: "a",
                authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                createdAt: .now.addingTimeInterval(-86_400), updatedAt: .now,
                reviewDecision: .none, checks: .none
            ),
            PullRequestItem(
                id: "new", number: 2, title: "t", repository: "r", author: "a",
                authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                createdAt: .now, updatedAt: .now.addingTimeInterval(-86_400),
                reviewDecision: .none, checks: .none
            ),
        ]
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == "new")
    }

    @Test("A list with no pull requests in it cannot be walked")
    func emptyList() {
        let (state, controller) = makeController()
        state.sidebarSelection = .mentions(repository: nil)
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == nil)
    }

    @Test("The keyboard walks the list the sidebar is pointing at")
    func followsTheSidebar() {
        let (state, controller) = makeController()
        let mine = SavedList(
            id: "mine", title: "Mine", query: "is:pr author:@me", content: .pullRequests
        )
        state.settings.savedLists += [mine]
        state.listPullRequests[mine.id] = [
            PullRequestItem(
                id: "mine-1", number: 9, title: "t", repository: "r", author: "avery",
                authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now, reviewDecision: .none, checks: .none
            ),
        ]
        state.sidebarSelection = .list(id: mine.id, repository: nil)
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == "mine-1")
    }
}

@MainActor
@Suite("The keyboard walks the list as drawn")
struct InspectionOrderTests {
    private func makeState() -> AppState {
        let defaults = TestDefaults.make()
        let state = AppState(settings: Settings(store: defaults))
        let list = SavedList(
            id: "l", title: "A list", query: "is:pr review-requested:@me", content: .pullRequests
        )
        state.settings.savedLists = [list]
        state.sidebarSelection = .list(id: list.id, repository: nil)
        // Interleaved repositories, so a grouped list is in a different
        // order from a flat one.
        state.listPullRequests[list.id] = [
            item(id: "a1", repository: "org/alpha", minutesAgo: 1),
            item(id: "b1", repository: "org/beta", minutesAgo: 2),
            item(id: "a2", repository: "org/alpha", minutesAgo: 3),
        ]
        return state
    }

    private func group(_ state: AppState) {
        guard var list = state.lists.first else { return }
        list.grouping = .byRepository
        state.settings.update(list)
    }

    private func item(id: String, repository: String, minutesAgo: Int) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: repository, author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now.addingTimeInterval(TimeInterval(-60 * minutesAgo)),
            reviewDecision: .none, checks: .none
        )
    }

    @Test("A flat list is walked in the order it is sorted")
    func flat() {
        let state = makeState()
        #expect(state.inspectableItems.map(\.id) == ["a1", "b1", "a2"])
    }

    /// The list's own arrow keys walk what is drawn. A menu item walking the
    /// ungrouped order would move the pane to a row somewhere else on screen.
    @Test("A grouped list is walked section by section")
    func grouped() {
        let state = makeState()
        group(state)
        #expect(state.inspectableItems.map(\.id) == ["a1", "a2", "b1"])
    }

    @Test("Moving follows the grouping too")
    func movingFollowsGrouping() {
        let state = makeState()
        group(state)
        let controller = RefreshController(state: state)
        state.inspectedPullRequestID = "a2"
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == "b1")
    }
}

@MainActor
@Suite("Notifications in the detail pane")
struct NotificationInspectionTests {
    private func makeState() -> (AppState, RefreshController) {
        let defaults = TestDefaults.make()
        let state = AppState(settings: Settings(store: defaults))
        state.settings.notificationReasons = [.mention]
        state.notifications = (1...3).map { index in
            NotificationItem(
                id: "n\(index)", title: "t", repository: "octo/platform", avatarURL: nil,
                reason: .mention, updatedAt: .now, subjectType: index == 1 ? "Issue" : "PullRequest",
                latestCommentAPIURL: nil, subjectAPIURL: nil
            )
        }
        state.sidebarSelection = .mentions(repository: nil)
        return (state, RefreshController(state: state))
    }

    @Test("Opening a notification puts it in the pane")
    func opens() {
        let (state, controller) = makeState()
        controller.inspect(state.notifications[1])
        #expect(state.inspectedNotification?.id == "n2")
        #expect(state.hasInspectorContent)
    }

    /// Without a comment to fetch there is nothing to wait for, and a
    /// spinner that never resolves is worse than a plain statement.
    @Test("A notification with no comment resolves to an empty message")
    func emptyPreview() {
        let (state, controller) = makeState()
        controller.inspect(state.notifications[0])
        #expect(state.previews["n1"] == .loaded(.none))
    }

    @Test("The keyboard walks the mentions too")
    func keyboard() {
        let (state, controller) = makeState()
        controller.moveInspection(by: 1)
        #expect(state.inspectedNotificationID == "n1")
        controller.moveInspection(by: 1)
        #expect(state.inspectedNotificationID == "n2")
        controller.moveInspection(by: -1)
        #expect(state.inspectedNotificationID == "n1")
    }

    /// The popover expands a row in place and the window opens a pane; one
    /// is not the other, and reading something in the popover should not
    /// rearrange a window behind it.
    @Test("The popover and the window open messages independently")
    func independentOfEachOther() {
        let (state, controller) = makeState()

        controller.togglePreview(for: state.notifications[0])
        #expect(state.expandedNotificationID == "n1")
        #expect(state.inspectedNotificationID == nil)

        controller.inspect(state.notifications[1])
        #expect(state.inspectedNotificationID == "n2")
        #expect(state.expandedNotificationID == "n1")

        // Closing the pane leaves the popover's row expanded.
        controller.closeInspector()
        #expect(state.inspectedNotificationID == nil)
        #expect(state.expandedNotificationID == "n1")

        // And closing the popover's row leaves the pane alone.
        controller.inspect(state.notifications[1])
        controller.togglePreview(for: state.notifications[0])
        #expect(state.expandedNotificationID == nil)
        #expect(state.inspectedNotificationID == "n2")
    }

    /// Grouped by type, the list draws the issues and the pull requests in
    /// their own sections; the keyboard has to follow what is drawn.
    @Test("Grouping the mentions changes the order walked")
    func grouped() {
        let (state, _) = makeState()
        state.settings.notificationGrouping = .byType
        // Two pull requests outnumber the one issue, so their section leads.
        #expect(state.inspectableNotifications.map(\.id) == ["n2", "n3", "n1"])
    }

    /// The pane describes a row in the list being looked at. A pull request
    /// opened before switching to the mentions is not that.
    @Test("The pane follows the sidebar, not whatever was opened last")
    func followsTheSidebar() {
        let (state, controller) = makeState()
        controller.inspect(state.notifications[0])
        let list = SavedList(
            id: "l", title: "A list", query: "is:pr review-requested:@me", content: .pullRequests
        )
        state.settings.savedLists = [list]
        state.listPullRequests[list.id] = [
            PullRequestItem(
                id: "pr", number: 1, title: "t", repository: "r", author: "a",
                authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now, reviewDecision: .none, checks: .none
            ),
        ]
        state.inspectedPullRequestID = "pr"

        #expect(state.hasInspectorContent)
        state.sidebarSelection = .list(id: list.id, repository: nil)
        #expect(state.inspectedPullRequest?.id == "pr")
        state.sidebarSelection = .dashboard
        #expect(!state.hasInspectorContent)
    }

    @Test("Closing the pane closes it for either list")
    func close() {
        let (state, controller) = makeState()
        controller.inspect(state.notifications[0])
        state.inspectedPullRequestID = "pr"
        controller.closeInspector()
        #expect(state.inspectedNotificationID == nil)
        #expect(state.inspectedPullRequestID == nil)
    }

    /// Marking a thread read drops it from the list, and the pane cannot go
    /// on describing something that is no longer there.
    @Test("A notification that is gone leaves the pane with nothing to show")
    func vanishes() {
        let (state, controller) = makeState()
        controller.inspect(state.notifications[0])
        state.notifications.removeAll { $0.id == "n1" }
        #expect(state.inspectedNotification == nil)
        #expect(!state.hasInspectorContent)
    }
}

@MainActor
@Suite("Refresh interval")
struct RefreshIntervalTests {
    private func settings() -> Settings {
        Settings(store: TestDefaults.make())
    }

    /// Assigning to a property from inside its own `didSet` re-enters the
    /// setter that @Observable generates, and the recursion overflows the
    /// stack: changing the interval in settings used to crash the app. If
    /// this test ever hangs or dies rather than failing, that is the reason.
    @Test("Changing the interval does not re-enter its own setter")
    func noRecursion() {
        let settings = settings()
        settings.refreshInterval = 900
        #expect(settings.refreshInterval == 900)
        settings.refreshInterval = 1800
        #expect(settings.refreshInterval == 1800)
    }

    @Test("The floor GitHub asks for is kept")
    func floor() {
        let settings = settings()
        settings.refreshInterval = 5
        #expect(settings.refreshInterval == Settings.minimumRefreshInterval)
    }

    @Test("The interval survives a restart")
    func persisted() {
        let defaults = TestDefaults.make()
        Settings(store: defaults).refreshInterval = 900
        #expect(Settings(store: defaults).refreshInterval == 900)
    }

    /// A value written by an older build, or by hand, must not outlive the
    /// floor either.
    @Test("A stored value below the floor is raised on load")
    func storedBelowFloor() {
        let defaults = TestDefaults.make()
        defaults.set(5.0, forKey: "refreshInterval")
        #expect(Settings(store: defaults).refreshInterval == Settings.minimumRefreshInterval)
    }
}

@MainActor
@Suite("The sender of a notification")
struct NotificationSenderTests {
    private func makeState(comments: Bool = true) -> (AppState, RefreshController) {
        let defaults = TestDefaults.make()
        let state = AppState(settings: Settings(store: defaults))
        state.settings.notificationReasons = [.mention]
        state.notifications = (1...3).map { index in
            NotificationItem(
                id: "n\(index)", title: "t", repository: "octo/platform", avatarURL: nil,
                reason: .mention, updatedAt: .now, subjectType: "Issue",
                latestCommentAPIURL: comments
                    ? URL(string: "https://api.github.com/repos/octo/platform/issues/comments/\(index)")
                    : nil,
                subjectAPIURL: nil
            )
        }
        return (state, RefreshController(state: state))
    }

    /// The API names nobody, so a thread with no comment to read has no
    /// sender to show -- and must not sit under a spinner for ever.
    @Test("A thread with no comment resolves at once and names nobody")
    func noComment() {
        let (state, controller) = makeState(comments: false)
        controller.loadPreviewIfNeeded(for: state.notifications[0])
        #expect(state.previews["n1"] == .loaded(.none))
        #expect(state.previews["n1"]?.preview?.author == nil)
    }

    /// Opening a row must not re-fetch a comment the list already has.
    @Test("A comment is read once per thread")
    func cached() {
        let (state, controller) = makeState()
        let known = PreviewState.loaded(
            CommentPreview(author: CommentAuthor(login: "mira", avatarURL: nil), body: "hi")
        )
        state.previews["n1"] = known
        controller.loadPreviewIfNeeded(for: state.notifications[0])
        #expect(state.previews["n1"] == known)
    }

    @Test("A fetch in flight is claimed, so a second one does not start")
    func claimed() {
        let (state, controller) = makeState()
        controller.loadPreviewIfNeeded(for: state.notifications[0])
        #expect(state.previews["n1"] == .loading)
    }

    @Test("The sender travels with the body it came from")
    func preview() {
        let preview = CommentPreview(
            author: CommentAuthor(login: "mira", avatarURL: URL(string: "https://e.com/a.png")),
            body: "hi"
        )
        #expect(PreviewState.loaded(preview).preview?.author?.login == "mira")
        #expect(PreviewState.loading.preview == nil)
        #expect(PreviewState.failed("nope").preview == nil)
    }
}
