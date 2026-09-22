import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Issue search")
struct IssueQueryTests {
    /// Assigned, open, and never a pull request: GitHub's search returns
    /// both kinds from the same index, so `is:issue` is what keeps the list
    /// from doubling up with the two pull request lists beside it.
    @Test("The search asks for open issues assigned to the user")
    func assignedQuery() {
        let query = IssueQuery.assignedQuery(login: "sidler", repositoryFilters: [])
        #expect(query.contains("is:issue"))
        #expect(query.contains("is:open"))
        #expect(query.contains("assignee:sidler"))
        #expect(!query.contains("is:pr"))
    }

    @Test("Repository filters narrow the search like everywhere else")
    func repositoryScope() {
        let query = IssueQuery.assignedQuery(
            login: "sidler",
            repositoryFilters: ["octo", "octo/platform"]
        )
        #expect(query.contains("org:octo"))
        #expect(query.contains("repo:octo/platform"))
    }

    /// One request carries every list, so a broken alias would take the
    /// pull requests down with the issues.
    @Test("The shared document carries the issue search under its own alias")
    func documentCarriesIssues() {
        let document = PullRequestQuery.document(
            reviewRequested: ["review-requested:me"],
            authored: ["author:me"],
            issues: ["assignee:me"]
        )
        #expect(document.contains("i0: search"))
        #expect(document.contains("...IssueResults"))
        #expect(document.contains("fragment IssueResults"))
        #expect(document.contains("fragment Results"))
    }

    /// GraphQL rejects a document that declares a fragment nothing uses, so
    /// an empty list must take its fragment with it.
    @Test("A document without issues declares no issue fragment")
    func documentWithoutIssues() {
        let document = PullRequestQuery.document(
            reviewRequested: ["review-requested:me"],
            authored: []
        )
        #expect(!document.contains("IssueResults"))
        #expect(document.contains("fragment Results"))
    }
}

@Suite("Issue parsing")
struct IssueParserTests {
    private func payload(_ nodes: [[String: Any]]) -> [String: Any] {
        ["i0": ["nodes": nodes]]
    }

    private var node: [String: Any] {
        [
            "id": "I_1",
            "number": 318,
            "title": "Session table migration order",
            "createdAt": "2026-09-01T08:00:00Z",
            "updatedAt": "2026-09-20T12:30:00Z",
            "url": "https://github.com/octo/platform/issues/318",
            "repository": ["nameWithOwner": "octo/platform"],
            "author": ["login": "mira", "avatarUrl": "https://avatars.githubusercontent.com/u/1"],
            "comments": ["totalCount": 7],
            "milestone": ["title": "8.3"],
            "labels": ["nodes": [["name": "bug", "color": "d73a4a"]]],
        ]
    }

    @Test("An issue is read with everything its row shows")
    func readsAnIssue() throws {
        let items = IssueParser.issues(from: payload([node]))
        let item = try #require(items.first)

        #expect(item.id == "I_1")
        #expect(item.number == 318)
        #expect(item.repository == "octo/platform")
        #expect(item.author == "mira")
        #expect(item.comments == 7)
        #expect(item.milestone == "8.3")
        #expect(item.labels.map(\.name) == ["bug"])
        #expect(item.createdAt < item.updatedAt)
    }

    /// A deleted account leaves the author null rather than omitting it, and
    /// a row with no author at all would be worse than one naming a ghost.
    @Test("Missing optional fields do not lose the issue")
    func tolerantOfMissingFields() throws {
        var sparse = node
        sparse["author"] = NSNull()
        sparse["comments"] = NSNull()
        sparse["milestone"] = NSNull()
        sparse["labels"] = NSNull()

        let item = try #require(IssueParser.issues(from: payload([sparse])).first)
        #expect(item.author == "ghost")
        #expect(item.comments == 0)
        #expect(item.milestone == nil)
        #expect(item.labels.isEmpty)
    }

    /// Search hits that are not issues come back as empty objects, and one
    /// of those must not become a row with no title.
    @Test("Anything that is not an issue is skipped")
    func skipsForeignNodes() {
        #expect(IssueParser.issues(from: payload([[:], ["id": "x"]])).isEmpty)
    }

    @Test("The same issue found twice is listed once")
    func deduplicates() {
        let items = IssueParser.issues(from: ["i0": ["nodes": [node]], "i1": ["nodes": [node]]])
        #expect(items.count == 1)
    }

    @Test("The detail carries the body and the end of the thread")
    func readsTheDetail() throws {
        let detail = try IssueQuery.detail(from: [
            "node": [
                "body": "The migration has to run **first**.",
                "comments": [
                    "totalCount": 12,
                    "nodes": [
                        [
                            "id": "C_1",
                            "createdAt": "2026-09-19T09:00:00Z",
                            "body": "Agreed.",
                            "author": ["login": "sidler", "avatarUrl": "https://example.com/a.png"],
                        ],
                    ],
                ],
            ],
        ])

        #expect(detail.body.contains("**first**"))
        #expect(detail.comments.map(\.author) == ["sidler"])
        #expect(detail.totalComments == 12)
        // The pane shows the tail of a long thread and has to say so.
        #expect(detail.olderComments == 11)
    }

    @Test("A payload without an issue is an error, not an empty pane")
    func detailNeedsANode() {
        #expect(throws: GitHubError.self) {
            try IssueQuery.detail(from: [:])
        }
    }
}

@Suite("Label colours")
struct IssueLabelTests {
    @Test("GitHub's hex colour is read as components")
    func readsColour() throws {
        let components = try #require(IssueLabel(name: "bug", color: "d73a4a").components)
        #expect(abs(components.red - 0.843) < 0.01)
        #expect(abs(components.green - 0.227) < 0.01)
        #expect(abs(components.blue - 0.290) < 0.01)
    }

    /// GitHub's palette runs from near-black to near-white, so one fixed
    /// text colour would make half the labels unreadable.
    @Test("Text colour follows the label's brightness", arguments: [
        ("fbca04", true),   // amber -- black text
        ("d73a4a", false),  // red -- white text
        ("ffffff", true),
        ("000000", false),
    ])
    func choosesReadableText(color: String, expectsDarkText: Bool) {
        #expect(IssueLabel(name: "l", color: color).prefersDarkText == expectsDarkText)
    }

    /// A colour that cannot be read is still a label, and the chip has to
    /// stay legible.
    @Test("An unreadable colour falls back to dark text")
    func toleratesNonsense() {
        #expect(IssueLabel(name: "l", color: "").components == nil)
        #expect(IssueLabel(name: "l", color: "nope").prefersDarkText)
    }
}

@MainActor
@Suite("The issue list")
struct IssueListTests {
    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.issues = [
            issue(id: "1", repository: "octo/platform", createdDaysAgo: 1, updatedMinutesAgo: 90),
            issue(id: "2", repository: "octo/platform", createdDaysAgo: 30, updatedMinutesAgo: 5),
            issue(id: "3", repository: "octo/octo.de", createdDaysAgo: 3, updatedMinutesAgo: 10),
        ]
        return state
    }

    private func issue(
        id: String,
        repository: String,
        createdDaysAgo: Int,
        updatedMinutesAgo: Int
    ) -> IssueItem {
        IssueItem(
            id: id, number: 1, title: "t", repository: repository, author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            createdAt: .now.addingTimeInterval(TimeInterval(-86400 * createdDaysAgo)),
            updatedAt: .now.addingTimeInterval(TimeInterval(-60 * updatedMinutesAgo))
        )
    }

    /// One switch orders every list: issues and pull requests answer the
    /// same question about different things.
    @Test("The list follows the sort chosen for the pull requests")
    func sharesTheSortSetting() {
        let state = makeState()
        state.settings.pullRequestSort = .updated
        #expect(state.visibleIssues.map(\.id) == ["2", "3", "1"])
        state.settings.pullRequestSort = .created
        #expect(state.visibleIssues.map(\.id) == ["1", "3", "2"])
    }

    @Test("The repository filter narrows the list and the count together")
    func repositoryFilter() {
        let state = makeState()
        state.settings.repositoryFilters = ["octo/platform"]
        #expect(state.visibleIssues.count == 2)
        #expect(state.issueRepositories.map(\.repository) == ["octo/platform"])
    }

    @Test("A sidebar repository narrows the list to it")
    func sidebarNarrows() {
        let state = makeState()
        state.sidebarSelection = .myIssues(repository: "octo/octo.de")
        #expect(state.selectedIssues.map(\.id) == ["3"])
    }

    /// The pane describes a row of the list on screen; a pull request opened
    /// earlier is not that.
    @Test("The detail pane only counts while the issue list is shown")
    func inspectorFollowsTheList() {
        let state = makeState()
        state.inspectedIssueID = "1"
        state.sidebarSelection = .myIssues(repository: nil)
        #expect(state.hasInspectorContent)
        #expect(state.inspectedIssue?.id == "1")

        state.sidebarSelection = .pullRequests(repository: nil)
        #expect(!state.hasInspectorContent)
        #expect(state.inspectableIssues.isEmpty)
    }

    /// An issue that was closed or handed on is gone from the list, and the
    /// pane must not keep describing it.
    @Test("An issue that leaves the list leaves the pane")
    func forgetsMissingIssues() {
        let state = makeState()
        state.inspectedIssueID = "1"
        state.issues = state.issues.filter { $0.id != "1" }
        #expect(state.inspectedIssue == nil)
    }

    @Test("The keyboard walks the list in the order it is drawn")
    func stepsThroughTheList() {
        let state = makeState()
        state.sidebarSelection = .myIssues(repository: nil)
        state.settings.pullRequestSort = .updated

        let items = state.inspectableIssues
        #expect(items.map(\.id) == ["2", "3", "1"])
        #expect(RefreshController.step(items, from: "3", by: 1)?.id == "1")
        #expect(RefreshController.step(items, from: "3", by: -1)?.id == "2")
        // The ends stop rather than wrap, as in every other list.
        #expect(RefreshController.step(items, from: "1", by: 1) == nil)
    }

    /// Issues have no draft state, so the toolbar's draft toggle has nothing
    /// to offer while this list is open.
    @Test("The draft count stays out of the issue list")
    func noDraftToggle() {
        let state = makeState()
        state.sidebarSelection = .myIssues(repository: nil)
        #expect(state.selectedDraftCount == 0)
    }

    /// Only the symbols the rows are using, as under the pull request list.
    @Test("The legend explains what the rows show")
    func legend() {
        #expect(IssueLegend.symbols(for: []).isEmpty)

        let withComments = IssueItem(
            id: "x", number: 1, title: "t", repository: "a/b", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            updatedAt: .now, comments: 3
        )
        #expect(IssueLegend.symbols(for: [withComments]) == [.comments])

        let withMilestone = IssueItem(
            id: "y", number: 2, title: "t", repository: "a/b", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            updatedAt: .now, milestone: "8.3"
        )
        #expect(IssueLegend.symbols(for: [withComments, withMilestone]) == [.comments, .milestone])
    }
}
