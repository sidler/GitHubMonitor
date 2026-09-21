import Foundation
import Testing
@testable import GitHubMonitorKit

@MainActor
@Suite("Sorting the pull request lists")
struct PullRequestSortTests {
    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        return AppState(settings: Settings(store: defaults))
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
        state.pullRequests = [
            item(id: "old-but-busy", openedDaysAgo: 30, updatedDaysAgo: 1),
            item(id: "fresh-and-quiet", openedDaysAgo: 2, updatedDaysAgo: 2),
        ]
        return state
    }

    @Test("By default the list follows the last activity")
    func defaultsToUpdated() {
        let state = loaded()
        #expect(state.settings.pullRequestSort == .updated)
        #expect(state.visiblePullRequests.map(\.id) == ["old-but-busy", "fresh-and-quiet"])
    }

    @Test("Sorting by date opened reads the other field")
    func byCreated() {
        let state = loaded()
        state.settings.pullRequestSort = .created
        #expect(state.visiblePullRequests.map(\.id) == ["fresh-and-quiet", "old-but-busy"])
    }

    @Test("The user's own list is ordered the same way")
    func authoredListToo() {
        let state = makeState()
        state.authoredPullRequests = [
            item(id: "old-but-busy", openedDaysAgo: 30, updatedDaysAgo: 1),
            item(id: "fresh-and-quiet", openedDaysAgo: 2, updatedDaysAgo: 2),
        ]
        state.settings.pullRequestSort = .created
        #expect(state.visibleAuthoredPullRequests.map(\.id) == ["fresh-and-quiet", "old-but-busy"])
    }

    /// Bots open pull requests in batches that share a timestamp to the
    /// second; without a tiebreak those rows would swap places on every
    /// refresh, under the reader's cursor.
    @Test("Rows with the same timestamp keep a stable order")
    func stableOrder() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        func tied(_ ids: [String]) -> [String] {
            let state = makeState()
            state.pullRequests = ids.map { id in
                PullRequestItem(
                    id: id, number: 1, title: "t", repository: "r", author: "a",
                    authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                    createdAt: moment, updatedAt: moment, reviewDecision: .none, checks: .none
                )
            }
            return state.visiblePullRequests.map(\.id)
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
        let suite = "githubmonitor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        Settings(store: defaults).pullRequestSort = .created
        #expect(Settings(store: defaults).pullRequestSort == .created)
    }

    @Test("Both orders are offered, and named")
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
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.pullRequests = (1...3).map { index in
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
        state.settings.pullRequestSort = .created
        state.pullRequests = [
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
        state.authoredPullRequests = [
            PullRequestItem(
                id: "mine", number: 9, title: "t", repository: "r", author: "sidler",
                authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now, reviewDecision: .none, checks: .none
            ),
        ]
        state.sidebarSelection = .myPullRequests(repository: nil)
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == "mine")
    }
}

@MainActor
@Suite("The keyboard walks the list as drawn")
struct InspectionOrderTests {
    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        // Interleaved repositories, so a grouped list is in a different
        // order from a flat one.
        state.pullRequests = [
            item(id: "a1", repository: "org/alpha", minutesAgo: 1),
            item(id: "b1", repository: "org/beta", minutesAgo: 2),
            item(id: "a2", repository: "org/alpha", minutesAgo: 3),
        ]
        return state
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
        state.settings.listGrouping = .byRepository
        #expect(state.inspectableItems.map(\.id) == ["a1", "a2", "b1"])
    }

    @Test("Moving follows the grouping too")
    func movingFollowsGrouping() {
        let state = makeState()
        state.settings.listGrouping = .byRepository
        let controller = RefreshController(state: state)
        state.inspectedPullRequestID = "a2"
        controller.moveInspection(by: 1)
        #expect(state.inspectedPullRequestID == "b1")
    }
}
