import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("How long a review has been waiting")
struct WaitingTests {
    private func node(requests: [(login: String?, team: String?, at: String)]) -> [String: Any] {
        var events: [[String: Any]] = []
        for request in requests {
            var reviewer: [String: Any] = [:]
            if let login = request.login { reviewer["login"] = login }
            if let team = request.team { reviewer["name"] = team }
            events.append(["createdAt": request.at, "requestedReviewer": reviewer])
        }
        return [
            "id": "1", "number": 1, "title": "t", "url": "https://github.com/a/b/pull/1",
            "updatedAt": "2026-09-20T10:00:00Z",
            "repository": ["nameWithOwner": "octo/platform"],
            "author": ["login": "mira"],
            "timelineItems": ["nodes": events],
        ]
    }

    private func date(_ iso: String) -> Date { GitHubDate.date(from: iso) }

    @Test("The clock starts when the review was asked of you")
    func namedRequest() throws {
        let item = try #require(PullRequestParser.pullRequest(
            from: node(requests: [(login: "sidler", team: nil, at: "2026-09-18T09:00:00Z")]),
            requestedOf: "sidler"
        ))
        #expect(item.reviewRequestedAt == date("2026-09-18T09:00:00Z"))
    }

    /// A request made of a team names the team. Treating that as a request
    /// of everyone in it would put a clock on pull requests nobody was
    /// personally asked about.
    @Test("A request made of a team is not a request of you")
    func teamRequest() throws {
        let item = try #require(PullRequestParser.pullRequest(
            from: node(requests: [(login: nil, team: "Frontend", at: "2026-09-18T09:00:00Z")]),
            requestedOf: "sidler"
        ))
        #expect(item.reviewRequestedAt == nil)
    }

    @Test("Someone else's request is not yours either")
    func otherPerson() throws {
        let item = try #require(PullRequestParser.pullRequest(
            from: node(requests: [(login: "chriskapp", team: nil, at: "2026-09-18T09:00:00Z")]),
            requestedOf: "sidler"
        ))
        #expect(item.reviewRequestedAt == nil)
    }

    /// Being asked a second time does not restart the clock: the question is
    /// how long this has been sitting, not when it was last mentioned.
    @Test("The earliest request counts, not the latest")
    func earliest() throws {
        let item = try #require(PullRequestParser.pullRequest(
            from: node(requests: [
                (login: "sidler", team: nil, at: "2026-09-19T09:00:00Z"),
                (login: "chriskapp", team: nil, at: "2026-09-17T09:00:00Z"),
                (login: "sidler", team: nil, at: "2026-09-18T09:00:00Z"),
            ]),
            requestedOf: "sidler"
        ))
        #expect(item.reviewRequestedAt == date("2026-09-18T09:00:00Z"))
    }

    @Test("Without a signed-in login nothing is claimed")
    func noViewer() throws {
        let item = try #require(PullRequestParser.pullRequest(
            from: node(requests: [(login: "sidler", team: nil, at: "2026-09-18T09:00:00Z")]),
            requestedOf: nil
        ))
        #expect(item.reviewRequestedAt == nil)
    }

    @Test("A login differing only in case is still you")
    func caseInsensitive() throws {
        let item = try #require(PullRequestParser.pullRequest(
            from: node(requests: [(login: "Sidler", team: nil, at: "2026-09-18T09:00:00Z")]),
            requestedOf: "sidler"
        ))
        #expect(item.reviewRequestedAt != nil)
    }

    // MARK: - What the row makes of it

    private func item(requestedAt: Date?) -> PullRequestItem {
        PullRequestItem(
            id: UUID().uuidString, number: 1, title: "t", repository: "octo/platform",
            author: "a", authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            isDraft: false, updatedAt: .now, reviewDecision: .reviewRequired, checks: .none,
            reviewRequestedAt: requestedAt
        )
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    @Test("The two thresholds decide what a row says")
    func thresholds() {
        func age(_ days: Double) -> WaitingAge? {
            WaitingAge.of(item(requestedAt: daysAgo(days)), agingDays: 3, overdueDays: 7, now: now)
        }
        #expect(age(0.5) == .fresh)
        #expect(age(2.9) == .fresh)
        #expect(age(3) == .aging)
        #expect(age(6.9) == .aging)
        #expect(age(7) == .overdue)
        #expect(age(30) == .overdue)
    }

    @Test("Nothing waiting has no age at all")
    func noClock() {
        #expect(WaitingAge.of(item(requestedAt: nil), agingDays: 3, overdueDays: 7, now: now) == nil)
    }

    /// Someone can put the louder threshold below the quieter one. The
    /// larger number is the louder step either way, rather than the order of
    /// two `if`s deciding it.
    @Test("Thresholds set the wrong way round still read sensibly")
    func invertedThresholds() {
        let waited = item(requestedAt: daysAgo(6))
        #expect(WaitingAge.of(waited, agingDays: 10, overdueDays: 4, now: now) == .aging)
        #expect(WaitingAge.of(item(requestedAt: daysAgo(12)), agingDays: 10, overdueDays: 4, now: now) == .overdue)
    }
}

@MainActor
@Suite("Ordering by how long something has waited")
struct WaitingSortTests {
    private let list = SavedList(
        id: "reviews", title: "Reviews", query: "is:pr review-requested:@me",
        content: .pullRequests, sort: .waiting
    )

    private func item(_ id: String, requestedAt: Date?, updated: Date) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: id, repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: updated, reviewDecision: .reviewRequired, checks: .none,
            reviewRequestedAt: requestedAt
        )
    }

    private func state(_ items: [PullRequestItem]) -> AppState {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        state.settings.savedLists = [list]
        state.listPullRequests[list.id] = items
        return state
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    @Test("Longest waiting first")
    func longestFirst() {
        let state = state([
            item("recent", requestedAt: daysAgo(1), updated: now),
            item("ancient", requestedAt: daysAgo(20), updated: now),
            item("middling", requestedAt: daysAgo(5), updated: now),
        ])
        #expect(state.pullRequests(in: list).map(\.id) == ["ancient", "middling", "recent"])
    }

    /// A list still shows everything it searched for. What nobody asked of
    /// you has no place in this ordering, so it follows in the usual one.
    @Test("What is not waiting on you goes last, newest first")
    func unaskedGoLast() {
        let state = state([
            item("mine-old", requestedAt: nil, updated: daysAgo(9)),
            item("waiting", requestedAt: daysAgo(2), updated: daysAgo(30)),
            item("mine-new", requestedAt: nil, updated: daysAgo(1)),
        ])
        #expect(state.pullRequests(in: list).map(\.id) == ["waiting", "mine-new", "mine-old"])
    }

    @Test("Only pull requests are offered the order")
    func offeredWhereItMeans() {
        #expect(ListContent.pullRequests.sorts.contains(.waiting))
        #expect(!ListContent.issues.sorts.contains(.waiting))
    }
}
