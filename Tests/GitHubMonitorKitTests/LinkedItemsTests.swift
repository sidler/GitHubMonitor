import Foundation
import Testing
@testable import GitHubMonitorKit

@MainActor
@Suite("What an item points at")
struct LinkedItemsTests {
    private let repository = "octo/platform"

    private let pullRequests = SavedList(
        id: "reviews", title: "Reviews", query: "is:pr review-requested:@me",
        content: .pullRequests
    )
    private let issues = SavedList(
        id: "mine", title: "Issues", query: "is:issue assignee:@me", content: .issues
    )

    private func item(
        number: Int = 482, links: [ItemLink] = [], linkedTotal: Int? = nil
    ) -> PullRequestItem {
        PullRequestItem(
            id: "pr-\(number)", number: number, title: "t", repository: repository,
            author: "a", authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            isDraft: false, updatedAt: .now, reviewDecision: .none, checks: .none,
            links: links, linkedTotal: linkedTotal
        )
    }

    private func issue(number: Int = 318, links: [ItemLink] = []) -> IssueItem {
        IssueItem(
            id: "i-\(number)", number: number, title: "t", repository: repository,
            author: "a", authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            updatedAt: .now, links: links
        )
    }

    private func link(_ number: Int, _ kind: ItemLink.Kind) -> ItemLink {
        ItemLink(reference: ItemReference(repository: repository, number: number), kind: kind)
    }

    private func state() -> AppState {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        state.settings.savedLists = [pullRequests, issues]
        return state
    }

    private func detail(body: String) -> PullRequestDetail {
        PullRequestDetail(
            headBranch: "b", baseBranch: "main", additions: 0, deletions: 0,
            changedFiles: 0, comments: 0, body: body, checks: [], reviewers: []
        )
    }

    /// The row knows what GitHub linked; the description adds the rest, and
    /// only once the description is there.
    @Test("Mentions in the description join the row's own links")
    func bodyJoinsIn() {
        let state = state()
        let pullRequest = item(links: [link(318, .closes)])

        #expect(state.links(of: pullRequest).map(\.reference.number) == [318])

        state.pullRequestDetails[pullRequest.id] = .loaded(detail(body: "Also see #4712."))
        let joined = state.links(of: pullRequest)
        #expect(joined.map(\.reference.number) == [318, 4712])
        #expect(joined.map(\.kind) == [.closes, .mentions])
    }

    /// A description that names its own number is talking about itself, and
    /// a panel offering to show you what you are reading is not an offer.
    @Test("An item does not link to itself")
    func noSelfLink() {
        let state = state()
        let pullRequest = item(number: 482)
        state.pullRequestDetails[pullRequest.id] = .loaded(
            detail(body: "Supersedes #482 in spirit.")
        )
        #expect(state.links(of: pullRequest).isEmpty)
    }

    /// GitHub counted eight; the query asked for five.
    @Test("Links GitHub counted but did not send are reported as a number")
    func overflow() {
        let state = state()
        #expect(state.unshownLinks(of: item(links: [link(1, .closes)], linkedTotal: 8)) == 7)
        #expect(state.unshownLinks(of: item(links: [link(1, .closes)], linkedTotal: 1)) == 0)
    }

    /// Mentions are read here, not counted by GitHub, so they must not make
    /// the "and N more" number go negative or shrink.
    @Test("Mentions do not count against GitHub's total")
    func mentionsDoNotCount() {
        let state = state()
        let pullRequest = item(links: [link(1, .closes), link(2, .mentions)], linkedTotal: 1)
        #expect(state.unshownLinks(of: pullRequest) == 0)
    }

    // MARK: - Going there

    @Test("An item in a list can be shown, and the sidebar follows")
    func reveal() {
        let state = state()
        let target = issue(number: 318)
        state.listIssues[issues.id] = [target]

        #expect(state.canReveal(target.reference))
        #expect(state.reveal(target.reference))
        #expect(state.sidebarSelection.listID == issues.id)
        #expect(state.inspectedIssueID == target.id)
        #expect(state.inspectedPullRequestID == nil)
    }

    @Test("An item in no list cannot be shown")
    func revealMissing() {
        let state = state()
        #expect(state.canReveal(ItemReference(repository: repository, number: 9999)) == false)
        #expect(state.reveal(ItemReference(repository: repository, number: 9999)) == false)
    }

    /// Going somewhere else means leaving the diff: it covers the whole
    /// window, including the row just selected.
    @Test("Showing an item puts away the diff being read")
    func revealClosesTheDiff() {
        let state = state()
        let target = item(number: 482)
        state.listPullRequests[pullRequests.id] = [target]
        state.openedDiff = OpenedDiff(
            pullRequestID: "other", path: "a.php", files: [], url: URL(string: "https://x.dev")!
        )

        #expect(state.reveal(target.reference))
        #expect(state.openedDiff == nil)
        #expect(state.inspectedPullRequestID == target.id)
    }

    /// The selection carries a repository narrowing, and the item revealed
    /// may not be in that repository.
    @Test("Showing an item drops any repository narrowing")
    func revealWidens() {
        let state = state()
        let target = item(number: 482)
        state.listPullRequests[pullRequests.id] = [target]
        state.sidebarSelection = .list(id: pullRequests.id, repository: "octo/other")

        #expect(state.reveal(target.reference))
        #expect(state.sidebarSelection.repository == nil)
    }
}
