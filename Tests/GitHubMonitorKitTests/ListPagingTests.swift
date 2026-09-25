import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Paging through a list")
struct ListPagingTests {
    private let reviews = ListSearch(
        listID: "reviews", content: .pullRequests, query: "is:pr review-requested:@me"
    )
    private let issues = ListSearch(
        listID: "issues", content: .issues, query: "is:issue assignee:@me"
    )

    private func node(id: String) -> [String: Any] {
        [
            "id": id, "number": 1, "title": "t", "url": "https://github.com/a/b/pull/1",
            "updatedAt": "2026-09-20T10:00:00Z",
            "repository": ["nameWithOwner": "octo/platform"],
            "author": ["login": "mira"],
        ]
    }

    private func search(
        _ nodes: [[String: Any]], total: Int, next: String? = nil
    ) -> [String: Any] {
        [
            "issueCount": total,
            "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any],
            "nodes": nodes,
        ]
    }

    /// The whole point: a queue of a hundred and nine used to arrive as
    /// fifty, and the badge counted the fifty.
    @Test("A search asks for a hundred at a time")
    func pageSize() {
        #expect(ListQuery.pageSize == 100)
        #expect(ListQuery.document([reviews]).contains("first: 100"))
    }

    @Test("A cursor is carried into the next request, and only where given")
    func cursors() {
        let document = ListQuery.document([reviews, issues], cursors: [1: "abc"])
        #expect(document.contains("after: \"abc\""))
        // The finished search is asked from the start again only if it is in
        // the batch at all; the one with no cursor carries none.
        #expect(document.components(separatedBy: "after:").count == 2)
    }

    @Test("Every search reports how many there are and where it stopped")
    func pages() {
        let payload: [String: Any] = [
            "s0": search([node(id: "1")], total: 109, next: "cursor-1"),
            "s1": search([], total: 4),
        ]
        let stops = ListParser.pages(from: payload, searches: [reviews, issues])
        #expect(stops[0]?.cursor == "cursor-1")
        #expect(stops[0]?.total == 109)
        // Nothing more to ask for, so no cursor even though one was sent.
        #expect(stops[1]?.cursor == nil)
        #expect(stops[1]?.total == 4)
    }

    /// Several searches can feed one list -- that is what the multi-line
    /// query is for -- so their totals add up the way their rows do.
    @Test("Totals of several searches add up per list")
    func totals() {
        let both = [
            ListSearch(listID: "reviews", content: .pullRequests, query: "a"),
            ListSearch(listID: "reviews", content: .pullRequests, query: "b"),
        ]
        let payload: [String: Any] = [
            "s0": search([node(id: "1")], total: 12),
            "s1": search([node(id: "2")], total: 5),
        ]
        let results = ListParser.results(from: payload, searches: both)
        #expect(results.totals["reviews"] == 17)
    }

    @Test("A page joins what is already held, without repeating it")
    func absorb() {
        var held = ListResults(pullRequests: ["reviews": [item(id: "1"), item(id: "2")]])
        held.absorb(ListResults(pullRequests: ["reviews": [item(id: "2"), item(id: "3")]]))
        #expect(held.pullRequests["reviews"]?.map(\.id) == ["1", "2", "3"])
        #expect(held.count(in: "reviews") == 3)
    }

    @Test("A list that found nothing still counts as read")
    func emptyList() {
        var held = ListResults()
        held.absorb(ListResults(issues: ["issues": []]))
        #expect(held.issues["issues"]?.isEmpty == true)
        #expect(held.count(in: "issues") == 0)
    }

    private func item(id: String) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
    }
}

@MainActor
@Suite("What a list is not showing")
struct UnshownTests {
    private let list = SavedList(
        id: "reviews", title: "Reviews", query: "is:pr review-requested:@me",
        content: .pullRequests
    )

    private func state(held: Int, total: Int?) -> AppState {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        state.settings.savedLists = [list]
        state.listPullRequests[list.id] = (0..<held).map { index in
            PullRequestItem(
                id: "\(index)", number: index, title: "t", repository: "octo/platform",
                author: "a", authorAvatarURL: nil, url: URL(string: "https://github.com")!,
                isDraft: false, updatedAt: .now, reviewDecision: .none, checks: .none
            )
        }
        if let total { state.listTotals[list.id] = total }
        return state
    }

    @Test("A list that fits hides nothing")
    func fits() {
        #expect(state(held: 109, total: 109).unshown(in: list) == 0)
    }

    @Test("A list past the cap says how many are left")
    func capped() {
        #expect(state(held: 300, total: 812).unshown(in: list) == 512)
    }

    /// Before the first refresh there is no total, and guessing one would
    /// put a number on the screen that nobody measured.
    @Test("Without a total nothing is claimed")
    func noTotal() {
        #expect(state(held: 4, total: nil).unshown(in: list) == 0)
    }
}
