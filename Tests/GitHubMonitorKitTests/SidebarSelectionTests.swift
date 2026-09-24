import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Sidebar selection")
struct SidebarSelectionTests {
    @Test("A selection points at one list, or at one of the fixed views")
    func listID() {
        #expect(SidebarSelection.list(id: "abc", repository: nil).listID == "abc")
        #expect(SidebarSelection.mentions(repository: nil).listID == nil)
        #expect(SidebarSelection.dashboard.listID == nil)
    }

    /// The switches are keyed by the same string the list is, and the
    /// mentions keep the one fixed key they always had.
    @Test("Selections map onto their visibility key")
    func visibilityKey() {
        #expect(SidebarSelection.list(id: "abc", repository: nil).visibilityKey == "abc")
        #expect(SidebarSelection.mentions(repository: nil).visibilityKey == ListVisibility.mentionsKey)
        #expect(SidebarSelection.settings.visibilityKey == nil)
    }

    /// An empty toolbar item is not nothing on macOS 26: every item gets its
    /// own glass background, so one hosting nothing shows as a sliver of
    /// glass beside the title.
    @Test("Only the views with controls ask for a toolbar item")
    func toolbarControls() {
        #expect(SidebarSelection.list(id: "a", repository: nil).hasToolbarControls)
        #expect(SidebarSelection.mentions(repository: nil).hasToolbarControls)
        for selection in [SidebarSelection.dashboard, .trends, .myTrends, .settings] {
            #expect(!selection.hasToolbarControls)
        }
    }

    /// Selections are used as list tags, so two entries that look alike must
    /// not compare equal.
    @Test("Selections for different lists and repositories are distinct")
    func distinctTags() {
        #expect(SidebarSelection.list(id: "a", repository: "x/y") != .list(id: "a", repository: "x/z"))
        #expect(SidebarSelection.list(id: "a", repository: nil) != .list(id: "b", repository: nil))
        #expect(SidebarSelection.list(id: "a", repository: nil) != .mentions(repository: nil))
    }
}

@MainActor
@Suite("Selection narrows the lists")
struct AppStateSelectionTests {
    private let reviews = SavedList(
        id: "reviews", title: "Reviews Requested",
        query: "is:pr review-requested:@me", content: .pullRequests
    )

    private func makeState() -> AppState {
        // An isolated defaults suite, so tests never touch the real settings.
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.settings.savedLists = [reviews]
        state.sidebarSelection = .list(id: reviews.id, repository: nil)
        // Explicit timestamps, newest first: the lists are sorted, so an
        // expectation on their order has to say what the order is.
        state.listPullRequests[reviews.id] = [
            pullRequest(id: "1", repository: "octo/platform", minutesAgo: 1),
            pullRequest(id: "2", repository: "octo/platform", minutesAgo: 2),
            pullRequest(id: "3", repository: "octo/octo.de", minutesAgo: 3),
        ]
        state.notifications = [notification(id: "n1", repository: "octo/platform")]
        return state
    }

    private func pullRequest(id: String, repository: String, minutesAgo: Int = 0) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: repository, author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now.addingTimeInterval(TimeInterval(-60 * minutesAgo)),
            reviewDecision: .none, checks: .none
        )
    }

    private func notification(id: String, repository: String) -> NotificationItem {
        NotificationItem(
            id: id, title: "t", repository: repository, avatarURL: nil,
            reason: .mention, updatedAt: .now, subjectType: "Issue",
            latestCommentAPIURL: nil, subjectAPIURL: nil
        )
    }

    @Test("'All' shows everything the list found")
    func allShowsEverything() {
        let state = makeState()
        #expect(state.selectedPullRequests(in: reviews).count == 3)
    }

    @Test("A repository selection narrows the list")
    func repositoryNarrows() {
        let state = makeState()
        state.sidebarSelection = .list(id: reviews.id, repository: "octo/platform")
        #expect(state.selectedPullRequests(in: reviews).map(\.id) == ["1", "2"])
    }

    /// The sidebar entries are what the user clicks, so their counts have to
    /// match what the list then shows.
    @Test("Sidebar counts match the narrowed lists")
    func countsMatchLists() {
        let state = makeState()
        for entry in state.repositories(in: reviews) {
            state.sidebarSelection = .list(id: reviews.id, repository: entry.repository)
            #expect(state.selectedPullRequests(in: reviews).count == entry.count)
        }
    }

    @Test("Repository entries are listed busiest first")
    func busiestFirst() {
        let state = makeState()
        #expect(state.repositories(in: reviews).map(\.repository) == [
            "octo/platform", "octo/octo.de",
        ])
        #expect(state.repositories(in: reviews).first?.count == 2)
    }

    /// The setting is about a row that says nothing, not about hiding
    /// repositories: with two of them the rows are what tells them apart.
    @Test("A lone repository row is dropped only when the setting asks")
    func lonelyRepositoryRow() {
        let one = [SidebarRepository(repository: "octo/platform", count: 3)]
        let two = one + [SidebarRepository(repository: "octo/octo.de", count: 1)]

        #expect(SidebarRepository.rows(one, collapsingSingle: true).isEmpty)
        #expect(SidebarRepository.rows(one, collapsingSingle: false) == one)
        #expect(SidebarRepository.rows(two, collapsingSingle: true) == two)
        #expect(SidebarRepository.rows([], collapsingSingle: true).isEmpty)
    }

    @Test("Mentions narrow independently of the lists")
    func mentionsNarrow() {
        let state = makeState()
        state.sidebarSelection = .mentions(repository: "octo/platform")
        #expect(state.selectedNotifications.count == 1)
        // A repository with no mentions yields an empty list, not everything.
        state.sidebarSelection = .mentions(repository: "octo/octo.de")
        #expect(state.selectedNotifications.isEmpty)
    }

    /// The title bar names the list, which the selection cannot know: it
    /// holds an id, and the title can be changed at any time.
    @Test("The title comes from the list, the subtitle from the repository")
    func titles() {
        let state = makeState()
        #expect(state.selectionTitle == "Reviews Requested")
        #expect(state.selectionSubtitle.isEmpty)

        state.sidebarSelection = .list(id: reviews.id, repository: "octo/platform")
        #expect(state.selectionTitle == "octo/platform")
        #expect(state.selectionSubtitle == "Reviews Requested")

        state.sidebarSelection = .dashboard
        #expect(state.selectionTitle == "Workload")
    }
}

@MainActor
@Suite("The draft toggle counts the list on screen")
struct DraftCountTests {
    private let reviews = SavedList(
        id: "reviews", title: "Reviews", query: "is:pr review-requested:@me", content: .pullRequests
    )
    private let mine = SavedList(
        id: "mine", title: "Mine", query: "is:pr author:@me", content: .pullRequests
    )

    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.settings.savedLists = [reviews, mine]
        state.listPullRequests[reviews.id] = [
            pullRequest(id: "1", repository: "octo/platform", draft: true),
            pullRequest(id: "2", repository: "octo/platform", draft: true),
            pullRequest(id: "3", repository: "octo/octo.de", draft: true),
            pullRequest(id: "4", repository: "octo/platform"),
        ]
        state.listPullRequests[mine.id] = [
            pullRequest(id: "5", repository: "octo/platform", draft: true),
            pullRequest(id: "6", repository: "octo/platform"),
        ]
        state.sidebarSelection = .list(id: reviews.id, repository: nil)
        return state
    }

    private func pullRequest(id: String, repository: String, draft: Bool = false) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: repository, author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: draft,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
    }

    @Test("The list on screen counts its own drafts")
    func listOnScreen() {
        let state = makeState()
        #expect(state.selectedDraftCount == 3)
    }

    /// The toggle sits in the toolbar above whichever list is open, so
    /// offering to show another list's drafts names a number the list on
    /// screen cannot account for.
    @Test("Another list's drafts are not counted")
    func otherList() {
        let state = makeState()
        state.sidebarSelection = .list(id: mine.id, repository: nil)
        #expect(state.selectedDraftCount == 1)
    }

    @Test("A repository selection narrows the count too")
    func narrowedByRepository() {
        let state = makeState()
        state.sidebarSelection = .list(id: reviews.id, repository: "octo/octo.de")
        #expect(state.selectedDraftCount == 1)
        state.sidebarSelection = .list(id: reviews.id, repository: "octo/platform")
        #expect(state.selectedDraftCount == 2)
    }

    /// Views without a list have no drafts to offer; a count above zero
    /// would put a toggle in a toolbar it does not belong in.
    @Test("Views that hold no list count nothing")
    func otherViews() {
        let state = makeState()
        for selection in [SidebarSelection.mentions(repository: nil), .dashboard, .settings] {
            state.sidebarSelection = selection
            #expect(state.selectedDraftCount == 0)
        }
    }

    /// Hiding drafts must not hide the offer to show them again.
    @Test("The count is the same whether drafts are shown or not")
    func independentOfVisibility() {
        let state = makeState()
        #expect(state.selectedDraftCount == 3)
        showDrafts(true, in: state)
        #expect(state.selectedDraftCount == 3)
        // What the list shows does change.
        #expect(state.pullRequests(in: state.list(withID: reviews.id)!).count == 4)
        showDrafts(false, in: state)
        #expect(state.pullRequests(in: state.list(withID: reviews.id)!).count == 1)
    }

    /// Each list answers for itself: a queue of what to review wants drafts
    /// out of the way while a list of one's own work is mostly drafts.
    @Test("Drafts are shown per list, not per app")
    func draftsPerList() {
        let state = makeState()
        showDrafts(true, in: state)
        #expect(state.pullRequests(in: state.list(withID: reviews.id)!).count == 4)
        // The other list was not asked to change with it, and still hides
        // the draft it holds.
        #expect(state.list(withID: mine.id)?.includeDrafts == false)
        #expect(state.pullRequests(in: state.list(withID: mine.id)!).count == 1)
    }

    private func showDrafts(_ shown: Bool, in state: AppState) {
        guard var list = state.list(withID: reviews.id) else { return }
        list.includeDrafts = shown
        state.settings.update(list)
    }
}
