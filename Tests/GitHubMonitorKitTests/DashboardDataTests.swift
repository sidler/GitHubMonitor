import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Dashboard data")
struct DashboardDataTests {
    private func item(author: String, draft: Bool = false, id: String = UUID().uuidString) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: author,
            authorAvatarURL: URL(string: "https://example.com/\(author).png"),
            url: URL(string: "https://github.com")!, isDraft: draft,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
    }

    @Test("Pull requests are counted per author")
    func perAuthor() throws {
        let data = DashboardData.summarise(
            [item(author: "a"), item(author: "a"), item(author: "b")],
            repository: "octo/platform"
        )
        #expect(data.authors.count == 2)
        #expect(data.authors.first { $0.author == "a" }?.ready == 2)
        #expect(data.authors.first { $0.author == "b" }?.ready == 1)
    }

    /// Drafts are not waiting on anyone; folding them into the same number
    /// would overstate how much review work an author has queued up.
    @Test("Drafts are counted apart from ready pull requests")
    func draftsSeparate() throws {
        let data = DashboardData.summarise(
            [item(author: "a"), item(author: "a", draft: true), item(author: "a", draft: true)],
            repository: "r"
        )
        let author = try #require(data.authors.first)
        #expect(author.ready == 1)
        #expect(author.drafts == 2)
        #expect(author.total == 3)
    }

    @Test("Totals add up across authors")
    func totals() {
        let data = DashboardData.summarise(
            [item(author: "a"), item(author: "b", draft: true), item(author: "c")],
            repository: "r"
        )
        #expect(data.totalReady == 2)
        #expect(data.totalDrafts == 1)
        #expect(data.total == 3)
    }

    /// The chart answers "who is waiting on a review", so an author with six
    /// drafts must not outrank one with two ready pull requests.
    @Test("Authors are ordered by work that is actually waiting")
    func orderedByReady() {
        let data = DashboardData.summarise(
            [item(author: "drafter", draft: true), item(author: "drafter", draft: true),
             item(author: "drafter", draft: true), item(author: "reviewer"),
             item(author: "reviewer")],
            repository: "r"
        )
        #expect(data.authors.map(\.author) == ["reviewer", "drafter"])
    }

    @Test("Equal counts fall back to name order so rows do not shuffle")
    func stableOrder() {
        let data = DashboardData.summarise(
            [item(author: "zoe"), item(author: "adam")],
            repository: "r"
        )
        #expect(data.authors.map(\.author) == ["adam", "zoe"])
    }

    @Test("An author with only drafts still appears")
    func draftsOnlyAuthor() throws {
        let data = DashboardData.summarise([item(author: "a", draft: true)], repository: "r")
        let author = try #require(data.authors.first)
        #expect(author.ready == 0)
        #expect(author.drafts == 1)
    }

    @Test("No pull requests yields no authors")
    func empty() {
        let data = DashboardData.summarise([PullRequestItem](), repository: "r")
        #expect(data.authors.isEmpty)
        #expect(data.total == 0)
    }

    @Test("The repository query is scoped to one repository")
    func repositoryQuery() {
        let query = PullRequestQuery.repositoryQuery("octo/platform")
        #expect(query.contains("repo:octo/platform"))
        #expect(query.contains("is:open"))
        // Drafts belong in the chart, so they must not be filtered out here.
        #expect(!query.contains("draft"))
        #expect(!query.contains("review-requested"))
    }
}

@Suite("Dashboard reviewer load")
struct DashboardReviewerTests {
    private func item(draft: Bool = false, id: String = UUID().uuidString) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "r", author: "someone",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: draft,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
    }

    private func reviewer(
        _ name: String,
        state: ReviewState,
        isTeam: Bool = false
    ) -> ReviewerStatus {
        ReviewerStatus(name: name, avatarURL: nil, state: state, isTeam: isTeam)
    }

    @Test("Outstanding reviews are counted per reviewer")
    func outstanding() throws {
        let data = DashboardData.summarise(
            [
                (item(), [reviewer("a", state: .pending), reviewer("b", state: .pending)]),
                (item(), [reviewer("a", state: .pending)]),
            ],
            repository: "r"
        )
        #expect(data.reviewers.first { $0.reviewer == "a" }?.pending == 2)
        #expect(data.reviewers.first { $0.reviewer == "b" }?.pending == 1)
        #expect(data.totalOutstandingReviews == 3)
    }

    /// A review already given is not outstanding; counting it would make an
    /// attentive reviewer look like the bottleneck.
    @Test("Reviews already given do not count as outstanding")
    func answeredReviewsExcluded() {
        let data = DashboardData.summarise(
            [(item(), [reviewer("a", state: .approved), reviewer("b", state: .changesRequested)])],
            repository: "r"
        )
        #expect(data.reviewers.isEmpty)
        #expect(data.totalOutstandingReviews == 0)
    }

    @Test("A reviewer with both answered and pending reviews keeps both counts")
    func mixedCounts() throws {
        let data = DashboardData.summarise(
            [
                (item(), [reviewer("a", state: .pending)]),
                (item(), [reviewer("a", state: .approved)]),
            ],
            repository: "r"
        )
        let load = try #require(data.reviewers.first)
        #expect(load.pending == 1)
        #expect(load.done == 1)
    }

    /// Nobody is blocked by a review request on a draft, so it belongs in its
    /// own segment rather than inflating the queue.
    @Test("Reviews owed on drafts are counted apart")
    func draftsApart() throws {
        let data = DashboardData.summarise(
            [
                (item(), [reviewer("a", state: .pending)]),
                (item(draft: true), [reviewer("a", state: .pending)]),
            ],
            repository: "r"
        )
        let load = try #require(data.reviewers.first)
        #expect(load.pending == 1)
        #expect(load.onDrafts == 1)
        #expect(load.outstanding == 2)
    }

    @Test("Teams appear as reviewers in their own right")
    func teams() throws {
        let data = DashboardData.summarise(
            [(item(), [reviewer("backend", state: .pending, isTeam: true)])],
            repository: "r"
        )
        let load = try #require(data.reviewers.first)
        #expect(load.reviewer == "backend")
        #expect(load.isTeam)
    }

    /// A user and a team can share a name; merging them would misreport both.
    @Test("A team and a user with the same name stay separate")
    func nameCollision() {
        let data = DashboardData.summarise(
            [(item(), [
                reviewer("core", state: .pending),
                reviewer("core", state: .pending, isTeam: true),
            ])],
            repository: "r"
        )
        #expect(data.reviewers.count == 2)
    }

    @Test("Reviewers are ordered by what is actually blocking")
    func ordering() {
        let data = DashboardData.summarise(
            [
                (item(draft: true), [reviewer("drafts-only", state: .pending)]),
                (item(draft: true), [reviewer("drafts-only", state: .pending)]),
                (item(draft: true), [reviewer("drafts-only", state: .pending)]),
                (item(), [reviewer("blocking", state: .pending)]),
            ],
            repository: "r"
        )
        #expect(data.reviewers.map(\.reviewer) == ["blocking", "drafts-only"])
    }

    @Test("Author counts are unaffected by the reviewer pass")
    func authorsStillCounted() {
        let data = DashboardData.summarise(
            [(item(), [reviewer("a", state: .pending)]), (item(draft: true), [])],
            repository: "r"
        )
        #expect(data.totalReady == 1)
        #expect(data.totalDrafts == 1)
    }
}

@Suite("A bar's pull requests")
struct WorkloadSelectionTests {
    private func item(
        id: String,
        author: String,
        draft: Bool = false,
        minutesAgo: Int = 0
    ) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: author,
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: draft,
            updatedAt: .now.addingTimeInterval(TimeInterval(-60 * minutesAgo)),
            reviewDecision: .none, checks: .none
        )
    }

    private func reviewer(_ name: String, state: ReviewState) -> ReviewerStatus {
        ReviewerStatus(name: name, avatarURL: nil, state: state, isTeam: false)
    }

    /// The bar is a number; the pane is what that number is made of. If they
    /// came from different fetches they would eventually disagree.
    @Test("An author's bar carries the pull requests it counted")
    func authorCarriesItsItems() throws {
        let data = DashboardData.summarise(
            [
                item(id: "1", author: "a", minutesAgo: 30),
                item(id: "2", author: "a", draft: true),
                item(id: "3", author: "a", minutesAgo: 5),
                item(id: "4", author: "b"),
            ],
            repository: "r"
        )
        let author = try #require(data.authors.first { $0.author == "a" })
        #expect(author.pullRequests.count == author.total)
        // What is waiting on someone comes first, newest activity at the top.
        #expect(author.pullRequests.map(\.id) == ["3", "1", "2"])

        let detail = WorkloadDetail(author)
        #expect(detail.ready.map(\.id) == ["3", "1"])
        #expect(detail.drafts.map(\.id) == ["2"])
    }

    /// The reviewer bar measures what is still owed, so the list under it
    /// must not include what they have already answered.
    @Test("A reviewer's bar lists only what is still waiting on them")
    func reviewerCarriesOutstandingOnly() throws {
        let data = DashboardData.summarise(
            [
                (item: item(id: "1", author: "a"), reviewers: [reviewer("r1", state: .pending)]),
                (item: item(id: "2", author: "b"), reviewers: [reviewer("r1", state: .approved)]),
                (
                    item: item(id: "3", author: "c", draft: true),
                    reviewers: [reviewer("r1", state: .pending)]
                ),
            ],
            repository: "r"
        )
        let load = try #require(data.reviewers.first)
        #expect(load.pending == 1)
        #expect(load.onDrafts == 1)
        #expect(load.done == 1)
        #expect(load.pullRequests.map(\.id) == ["1", "3"])
    }
}

@MainActor
@Suite("Clicking a workload bar")
struct WorkloadInspectorTests {
    private func makeState() -> AppState {
        let defaults = TestDefaults.make()
        let state = AppState(settings: Settings(store: defaults))
        state.sidebarSelection = .dashboard
        state.settings.dashboardRepository = "octo/platform"
        state.dashboard = .loaded(
            DashboardData.summarise(
                [
                    (
                        item: PullRequestItem(
                            id: "1", number: 1, title: "t", repository: "octo/platform",
                            author: "mira", authorAvatarURL: nil,
                            url: URL(string: "https://github.com")!, isDraft: false,
                            updatedAt: .now, reviewDecision: .none, checks: .none
                        ),
                        reviewers: [
                            ReviewerStatus(name: "sidler", avatarURL: nil, state: .pending, isTeam: false),
                        ]
                    ),
                ],
                repository: "octo/platform"
            )
        )
        return state
    }

    @Test("The pane lists the pull requests behind the bar")
    func listsTheBarsPullRequests() throws {
        let state = makeState()
        state.workloadSelection = WorkloadSelection(grouping: .author, id: "mira")

        let detail = try #require(state.inspectedWorkload)
        #expect(detail.title == "mira")
        #expect(detail.pullRequests.map(\.id) == ["1"])
        #expect(state.hasInspectorContent)
    }

    /// The same login means different things in the two charts, so a
    /// selection made in one must not describe a bar in the other.
    @Test("Switching the chart puts the pane away")
    func groupingChangeClosesIt() {
        let state = makeState()
        state.workloadSelection = WorkloadSelection(grouping: .author, id: "mira")
        state.settings.dashboardGrouping = .reviewer
        #expect(state.inspectedWorkload == nil)
        #expect(!state.hasInspectorContent)
    }

    @Test("The reviewer chart lists what is waiting on that person")
    func reviewerSelection() throws {
        let state = makeState()
        state.settings.dashboardGrouping = .reviewer
        state.workloadSelection = WorkloadSelection(grouping: .reviewer, id: "user:sidler")

        let detail = try #require(state.inspectedWorkload)
        #expect(detail.title == "sidler")
        #expect(detail.pullRequests.map(\.id) == ["1"])
    }

    /// A reload can drop a person from the chart entirely, and a pane
    /// describing somebody no longer drawn describes nothing.
    @Test("A bar that disappears takes its pane with it")
    func staleSelection() {
        let state = makeState()
        state.workloadSelection = WorkloadSelection(grouping: .author, id: "someone-else")
        #expect(state.inspectedWorkload == nil)
    }

    /// A chart has no row to click away from, so the same bar twice has to
    /// close what it opened.
    @Test("Clicking the same bar twice closes the pane")
    func toggles() {
        let state = makeState()
        let controller = RefreshController(state: state)
        let selection = WorkloadSelection(grouping: .author, id: "mira")

        controller.toggleWorkload(selection)
        #expect(state.workloadSelection == selection)
        controller.toggleWorkload(selection)
        #expect(state.workloadSelection == nil)
    }

    @Test("The keyboard walks the bars from top to bottom")
    func stepsThroughBars() {
        let state = makeState()
        let bars = state.inspectableWorkload
        #expect(bars.map(\.id) == ["mira"])
        #expect(RefreshController.step(bars, from: nil, by: 1)?.id == "mira")
        #expect(RefreshController.step(bars, from: "mira", by: 1) == nil)
    }

    /// Only while the chart is the view on screen: the pane belongs to it.
    @Test("The selection is ignored outside the workload view")
    func onlyOnTheDashboard() {
        let state = makeState()
        state.workloadSelection = WorkloadSelection(grouping: .author, id: "mira")
        state.sidebarSelection = .list(id: "some-list", repository: nil)
        #expect(state.inspectedWorkload == nil)
        #expect(state.inspectableWorkload.isEmpty)
    }
}

@Suite("The chart admits what it did not read")
struct DashboardTruncationTests {
    private func page(nodes: Int, total: Int, cursor: String?) -> [String: Any] {
        [
            "d0": [
                "issueCount": total,
                "pageInfo": ["hasNextPage": cursor != nil, "endCursor": cursor as Any],
                "nodes": (0..<nodes).map { index in
                    [
                        "id": "\(index)", "number": index, "title": "t",
                        "url": "https://github.com/a/b/pull/\(index)",
                        "updatedAt": "2026-09-20T10:00:00Z",
                        "repository": ["nameWithOwner": "octo/platform"],
                        "author": ["login": "mira"],
                    ] as [String: Any]
                },
            ],
        ]
    }

    /// The chart used to ask for one page of a hundred and add it up as
    /// though it were everything. Measured on the repository this was
    /// written for: 210 open pull requests.
    @Test("A page says how many there are and where to carry on")
    func pageReading() {
        let read = PullRequestParser.repositoryPage(from: page(nodes: 100, total: 210, cursor: "next"))
        #expect(read.entries.count == 100)
        #expect(read.total == 210)
        #expect(read.cursor == "next")

        let last = PullRequestParser.repositoryPage(from: page(nodes: 10, total: 210, cursor: nil))
        #expect(last.cursor == nil)
    }

    @Test("What was not read is what the chart is missing")
    func unread() {
        let complete = DashboardData(repository: "a/b", authors: [], unread: 0)
        #expect(complete.unread == 0)

        let short = DashboardData(repository: "a/b", authors: [], unread: 512)
        #expect(short.unread == 512)
    }

    /// GitHub counts at the moment it is asked, and a pull request merged
    /// between two pages leaves the count one above the rows. Reading that
    /// as "one not counted" would put a warning on a complete chart --
    /// measured while writing this: 210 on the first page, 209 rows.
    @Test("A count that drifts while paging is not a missing page")
    func drift() {
        #expect(PullRequestQuery.unread(total: 210, read: 209, stoppedEarly: false) == 0)
    }

    @Test("Stopping at the cap is what gets reported")
    func stoppedAtTheCap() {
        #expect(PullRequestQuery.unread(total: 1500, read: 1000, stoppedEarly: true) == 500)
        // Never below nothing, however the count drifted.
        #expect(PullRequestQuery.unread(total: 900, read: 1000, stoppedEarly: true) == 0)
    }

    @Test("A response that is not a search is empty, not a crash")
    func malformed() {
        let read = PullRequestParser.repositoryPage(from: [:])
        #expect(read.entries.isEmpty)
        #expect(read.total == 0)
        #expect(read.cursor == nil)
    }
}
