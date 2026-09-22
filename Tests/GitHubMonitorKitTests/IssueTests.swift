import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Issue parsing")
struct IssueParserTests {
    private func payload(_ nodes: [[String: Any]]) -> [String: Any] {
        [ListQuery.alias(0): ["nodes": nodes]]
    }

    private func parse(_ payload: [String: Any], searches: Int = 1) -> [IssueItem] {
        ListParser.results(
            from: payload,
            searches: (0..<searches).map {
                ListSearch(listID: "l", content: .issues, query: "q\($0)")
            }
        )
        .issues["l"] ?? []
    }

    private var node: [String: Any] {
        [
            "issueType": ["name": "Bug", "color": "RED"],
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
        let items = parse(payload([node]))
        let item = try #require(items.first)

        #expect(item.id == "I_1")
        #expect(item.number == 318)
        #expect(item.repository == "octo/platform")
        #expect(item.author == "mira")
        #expect(item.comments == 7)
        #expect(item.milestone == "8.3")
        #expect(item.labels.map(\.name) == ["bug"])
        #expect(item.type == IssueType(name: "Bug", color: .red))
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
        sparse["issueType"] = NSNull()

        let item = try #require(parse(payload([sparse])).first)
        #expect(item.author == "ghost")
        #expect(item.comments == 0)
        #expect(item.milestone == nil)
        #expect(item.labels.isEmpty)
        #expect(item.type == nil)
        // The list still has somewhere to file it.
        #expect(item.typeName == IssueItem.untyped)
    }

    /// A colour GitHub adds later must not cost us the type's name.
    @Test("An unknown type colour falls back to the neutral one")
    func unknownColour() throws {
        var node = self.node
        node["issueType"] = ["name": "Chore", "color": "CHARTREUSE"]
        let item = try #require(parse(payload([node])).first)
        #expect(item.type == IssueType(name: "Chore", color: .gray))
    }

    /// Search hits that are not issues come back as empty objects, and one
    /// of those must not become a row with no title.
    @Test("Anything that is not an issue is skipped")
    func skipsForeignNodes() {
        #expect(parse(payload([[:], ["id": "x"]])).isEmpty)
    }

    @Test("The same issue found twice is listed once")
    func deduplicates() {
        let items = parse(
            [ListQuery.alias(0): ["nodes": [node]], ListQuery.alias(1): ["nodes": [node]]],
            searches: 2
        )
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
@Suite("An issue list")
struct IssueListTests {
    private let list = SavedList(
        id: "l", title: "My Issues", query: "is:issue assignee:@me", content: .issues
    )

    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.settings.savedLists = [list]
        state.sidebarSelection = .list(id: list.id, repository: nil)
        state.listIssues[list.id] = [
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

    private func ordered(_ state: AppState, by sort: ListSort) -> [String] {
        var updated = list
        updated.sort = sort
        state.settings.update(updated)
        return state.issues(in: updated).map(\.id)
    }

    @Test("The list follows its own order")
    func sorting() {
        let state = makeState()
        #expect(ordered(state, by: .updated) == ["2", "3", "1"])
        #expect(ordered(state, by: .created) == ["1", "3", "2"])
    }

    @Test("A sidebar repository narrows the list to it")
    func sidebarNarrows() {
        let state = makeState()
        state.sidebarSelection = .list(id: list.id, repository: "octo/octo.de")
        #expect(state.selectedIssues(in: list).map(\.id) == ["3"])
    }

    /// The pane describes a row of the list on screen; something opened in
    /// another list is not that.
    @Test("The detail pane only counts while the issue list is shown")
    func inspectorFollowsTheList() {
        let state = makeState()
        state.inspectedIssueID = "1"
        #expect(state.hasInspectorContent)
        #expect(state.inspectedIssue?.id == "1")

        state.sidebarSelection = .dashboard
        #expect(!state.hasInspectorContent)
        #expect(state.inspectableIssues.isEmpty)
    }

    /// An issue that was closed or handed on is gone from the list, and the
    /// pane must not keep describing it.
    @Test("An issue that leaves the list leaves the pane")
    func forgetsMissingIssues() {
        let state = makeState()
        state.inspectedIssueID = "1"
        state.listIssues[list.id] = state.listIssues[list.id]?.filter { $0.id != "1" }
        #expect(state.inspectedIssue == nil)
    }

    @Test("The keyboard walks the list in the order it is drawn")
    func stepsThroughTheList() {
        let state = makeState()
        let items = state.inspectableIssues
        #expect(items.map(\.id) == ["2", "3", "1"])
        #expect(RefreshController.step(items, from: "3", by: 1)?.id == "1")
        #expect(RefreshController.step(items, from: "3", by: -1)?.id == "2")
        // The ends stop rather than wrap, as in every other list.
        #expect(RefreshController.step(items, from: "1", by: 1) == nil)
    }

    /// Issues have no draft state, so the toolbar's draft toggle has nothing
    /// to offer while this list is open.
    @Test("The draft count stays out of an issue list")
    func noDraftToggle() {
        #expect(makeState().selectedDraftCount == 0)
    }

    /// Only the symbols the rows are using, as under a pull request list.
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

@Suite("Issue types")
struct IssueTypeTests {
    private func issue(
        id: String,
        type: IssueType?,
        repository: String = "a/b",
        minutesAgo: Int = 0
    ) -> IssueItem {
        IssueItem(
            id: id, number: 1, title: "t", repository: repository, author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            updatedAt: .now.addingTimeInterval(TimeInterval(-60 * minutesAgo)),
            type: type
        )
    }

    private let bug = IssueType(name: "Bug", color: .red)
    private let task = IssueType(name: "Task", color: .blue)
    private let epic = IssueType(name: "Epic", color: .purple)

    /// Named types read alphabetically; the untyped bucket goes last rather
    /// than sorting under "N".
    @Test("Sorting by type groups the named types first")
    func sortByType() {
        let items = [
            issue(id: "1", type: task),
            issue(id: "2", type: nil),
            issue(id: "3", type: bug, minutesAgo: 10),
            issue(id: "4", type: bug, minutesAgo: 1),
            issue(id: "5", type: epic),
        ]
        let sorted = IssueFilter.sorted(items, by: .type)
        #expect(sorted.map(\.id) == ["4", "3", "5", "1", "2"])
    }

    @Test("The other orders are unaffected by the type")
    func sortByDate() {
        let items = [
            issue(id: "1", type: task, minutesAgo: 10),
            issue(id: "2", type: nil, minutesAgo: 1),
        ]
        #expect(IssueFilter.sorted(items, by: .updated).map(\.id) == ["2", "1"])
    }

    /// The menu is read by name, so it must not reshuffle as counts change.
    @Test("The filter offers every type by name, untyped last")
    func tallies() {
        let tallies = IssueFilter.tallies(of: [
            issue(id: "1", type: task),
            issue(id: "2", type: task),
            issue(id: "3", type: bug),
            issue(id: "4", type: nil),
        ])
        #expect(tallies.map(\.name) == ["Bug", "Task", IssueItem.untyped])
        #expect(tallies.map(\.count) == [1, 2, 1])
        #expect(tallies.last?.isUntyped == true)
        #expect(tallies.first?.color == .red)
    }

    @Test("Hiding a type takes it out of the list")
    func filtering() {
        let items = [
            issue(id: "1", type: task),
            issue(id: "2", type: bug),
            issue(id: "3", type: nil),
        ]
        let shown = IssueFilter.apply(items, hiddenTypes: ["Task"], repositoryFilters: [])
        #expect(shown.map(\.id) == ["2", "3"])

        // The untyped bucket is a type like any other as far as the filter
        // is concerned, or there would be no way to hide it.
        let typedOnly = IssueFilter.apply(
            items, hiddenTypes: [IssueItem.untyped], repositoryFilters: []
        )
        #expect(typedOnly.map(\.id) == ["1", "2"])
    }

    @Test("The type filter and the repository filter both apply")
    func combinedWithRepositoryFilter() {
        let items = [
            issue(id: "1", type: task, repository: "octo/platform"),
            issue(id: "2", type: bug, repository: "octo/platform"),
            issue(id: "3", type: task, repository: "other/thing"),
        ]
        let shown = IssueFilter.apply(
            items, hiddenTypes: ["Bug"], repositoryFilters: ["octo"]
        )
        #expect(shown.map(\.id) == ["1"])
    }
}

@MainActor
@Suite("An issue list, by type")
struct IssueTypeListTests {
    private let list = SavedList(
        id: "l", title: "Issues", query: "is:issue assignee:@me", content: .issues
    )

    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.settings.savedLists = [list]
        state.sidebarSelection = .list(id: list.id, repository: nil)
        state.listIssues[list.id] = [
            issue(id: "1", type: IssueType(name: "Task", color: .blue)),
            issue(id: "2", type: IssueType(name: "Bug", color: .red)),
            issue(id: "3", type: nil),
        ]
        return state
    }

    private func issue(id: String, type: IssueType?) -> IssueItem {
        IssueItem(
            id: id, number: 1, title: "t", repository: "a/b", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            updatedAt: .now, type: type
        )
    }

    private func hide(_ types: Set<String>, on state: AppState) -> SavedList {
        var updated = list
        updated.hiddenTypes = types
        state.settings.update(updated)
        return updated
    }

    /// A type switched off has to stay in the menu, or there is no way to
    /// switch it back on.
    @Test("The filter menu keeps offering what it is hiding")
    func menuKeepsHiddenTypes() {
        let state = makeState()
        let updated = hide(["Bug"], on: state)

        #expect(Set(state.issues(in: updated).map(\.id)) == ["1", "3"])
        #expect(state.selectedTypeTallies.map(\.name) == ["Bug", "Task", IssueItem.untyped])
        #expect(state.hiddenIssueCount == 1)
    }

    /// The menu item that walks the list has to walk what is drawn, section
    /// by section, or it sends the detail pane somewhere else on screen.
    @Test("The keyboard follows the grouping on screen")
    func inspectionFollowsGrouping() {
        let state = makeState()
        var updated = list
        updated.grouping = .byType
        state.settings.update(updated)

        // Sections are ordered by size and then by name, as every grouped
        // list in the app is; here all three hold one issue.
        #expect(state.inspectableIssues.map(\.typeName) == ["Bug", IssueItem.untyped, "Task"])
    }

    @Test("Ordering by type reorders the list itself")
    func sorting() {
        let state = makeState()
        var updated = list
        updated.sort = .type
        state.settings.update(updated)
        #expect(state.issues(in: updated).map(\.id) == ["2", "1", "3"])
    }

    /// The window's count follows the list, filter and all -- a number the
    /// list cannot account for is worse than no number.
    @Test("A hidden type is not counted either")
    func countFollowsTheFilter() {
        let state = makeState()
        #expect(state.count(of: list) == 3)
        #expect(state.count(of: hide(["Task", "Bug"], on: state)) == 1)
    }
}
