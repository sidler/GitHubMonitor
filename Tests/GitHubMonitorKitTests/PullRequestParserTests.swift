import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Pull request parser")
struct PullRequestParserTests {
    /// One list, one search, as the refresh sends it.
    private func parse(_ payloads: [[[String: Any]]], listID: String = "l") -> [PullRequestItem] {
        var payload: [String: Any] = [:]
        var searches: [ListSearch] = []
        for (index, nodes) in payloads.enumerated() {
            payload[ListQuery.alias(index)] = ["nodes": nodes]
            searches.append(ListSearch(listID: listID, content: .pullRequests, query: "q\(index)"))
        }
        return ListParser.results(from: payload, searches: searches).pullRequests[listID] ?? []
    }

    private func node(
        id: String,
        updated: String = "2026-09-20T10:00:00Z",
        draft: Bool = false,
        decision: Any? = "REVIEW_REQUIRED",
        rollup: Any? = "SUCCESS"
    ) -> [String: Any] {
        var node: [String: Any] = [
            "id": id,
            "number": 7,
            "title": "Title \(id)",
            "isDraft": draft,
            "updatedAt": updated,
            "url": "https://github.com/octo/server/pull/7",
            "repository": ["nameWithOwner": "octo/server"],
            "author": ["login": "mira", "avatarUrl": "https://example.com/a.png"],
        ]
        if let decision { node["reviewDecision"] = decision }
        if let rollup {
            node["commits"] = ["nodes": [["commit": ["statusCheckRollup": ["state": rollup]]]]]
        }
        return node
    }

    /// The list can be ordered by either date, so both have to survive the
    /// trip out of the payload.
    @Test("Both timestamps are read")
    func timestamps() throws {
        var raw = node(id: "a", updated: "2026-09-19T10:00:00Z")
        raw["createdAt"] = "2026-09-01T08:30:00Z"
        let items = parse([[raw]])
        let item = try #require(items.first)
        #expect(item.createdAt == GitHubDate.date(from: "2026-09-01T08:30:00Z"))
        #expect(item.updatedAt == GitHubDate.date(from: "2026-09-19T10:00:00Z"))
        #expect(item.date(for: .created) == item.createdAt)
        #expect(item.date(for: .updated) == item.updatedAt)
    }

    @Test("Fields are mapped across")
    func mapping() throws {
        let items = parse([[node(id: "a")]])
        let item = try #require(items.first)
        #expect(item.number == 7)
        #expect(item.repository == "octo/server")
        #expect(item.author == "mira")
        #expect(item.authorAvatarURL?.absoluteString == "https://example.com/a.png")
        #expect(item.reviewDecision == .reviewRequired)
        #expect(item.checks == .success)
    }

    /// A pull request requested from the user personally and from one of
    /// their teams is found by two of a list's searches; counting it twice
    /// would inflate the menu bar badge.
    @Test("The same pull request in two of a list's searches is counted once")
    func deduplication() {
        let items = parse([
            [node(id: "same"), node(id: "only-personal")],
            [node(id: "same"), node(id: "only-team")],
        ])
        #expect(items.count == 3)
        #expect(Set(items.map(\.id)) == ["same", "only-personal", "only-team"])
    }

    /// Search results also contain issues, which arrive as empty objects
    /// because the fragment only matches pull requests.
    @Test("Non-pull-request hits are skipped")
    func skipsUnusableNodes() {
        #expect(parse([[[:], node(id: "real")]]).map(\.id) == ["real"])
    }

    @Test("A deleted author does not drop the pull request")
    func missingAuthor() throws {
        var raw = node(id: "a")
        raw["author"] = NSNull()
        let items = parse([[raw]])
        let item = try #require(items.first)
        #expect(item.author == "ghost")
        #expect(item.authorAvatarURL == nil)
    }

    @Test("Absent review decision and checks degrade to 'none'")
    func absentOptionalFields() throws {
        let items = parse([[node(id: "a", decision: nil, rollup: nil)]])
        let item = try #require(items.first)
        #expect(item.reviewDecision == .none)
        #expect(item.checks == .none)
    }

    @Test("Check rollup states map onto the model", arguments: [
        ("SUCCESS", ChecksStatus.success),
        ("FAILURE", ChecksStatus.failure),
        ("ERROR", ChecksStatus.failure),
        ("PENDING", ChecksStatus.pending),
        ("SOMETHING_NEW", ChecksStatus.none),
    ])
    func rollupStates(raw: String, expected: ChecksStatus) throws {
        let items = parse([[node(id: "a", rollup: raw)]])
        #expect(try #require(items.first).checks == expected)
    }

    /// One document carries every list; a parser that lost track of which
    /// alias belonged to which would show one list's rows in another.
    @Test("Lists are kept apart by their alias")
    func listsAreSeparate() {
        let payload: [String: Any] = [
            ListQuery.alias(0): ["nodes": [node(id: "to-review")]],
            ListQuery.alias(1): ["nodes": [node(id: "mine")]],
        ]
        let results = ListParser.results(from: payload, searches: [
            ListSearch(listID: "reviews", content: .pullRequests, query: "a"),
            ListSearch(listID: "authored", content: .pullRequests, query: "b"),
        ])
        #expect(results.pullRequests["reviews"]?.map(\.id) == ["to-review"])
        #expect(results.pullRequests["authored"]?.map(\.id) == ["mine"])
    }

    /// A list that ran and found nothing is not the same as a list that was
    /// never asked: the first shows "nothing matches", the second nothing.
    @Test("A list that found nothing still gets an answer")
    func emptyPayload() {
        let results = ListParser.results(from: [:], searches: [
            ListSearch(listID: "l", content: .pullRequests, query: "a"),
        ])
        #expect(results.pullRequests["l"] == [])
        #expect(parse([[]]).isEmpty)
    }
}

@Suite("Review tally")
struct ReviewTallyTests {
    private func node(
        opinions: [String]? = nil,
        latestReviews: [String]? = nil,
        requested: Int? = nil
    ) -> [String: Any] {
        var node: [String: Any] = [
            "id": "a",
            "number": 7,
            "title": "Title",
            "url": "https://github.com/octo/server/pull/7",
            "updatedAt": "2026-09-20T10:00:00Z",
        ]
        if let opinions {
            node["latestOpinionatedReviews"] = ["nodes": opinions.map { ["state": $0] }]
        }
        if let latestReviews {
            node["latestReviews"] = ["nodes": latestReviews.map { ["state": $0] }]
        }
        if let requested {
            node["reviewRequests"] = ["totalCount": requested]
        }
        return node
    }

    private func tally(_ node: [String: Any]) throws -> ReviewTally {
        try #require(PullRequestParser.pullRequest(from: node)).reviews
    }

    @Test("Opinions and outstanding requests are counted apart")
    func counts() throws {
        let result = try tally(node(
            opinions: ["APPROVED", "APPROVED", "CHANGES_REQUESTED"],
            requested: 4
        ))
        #expect(result.accepted == 2)
        #expect(result.declined == 1)
        #expect(result.pending == 4)
        #expect(result.total == 7)
    }

    /// A comment is not a verdict, and neither is a dismissed review; counting
    /// either as an approval would report a pull request as further along
    /// than it is.
    @Test("Only approvals and change requests count as opinions")
    func opinionsOnly() throws {
        let result = try tally(node(opinions: ["COMMENTED", "DISMISSED", "PENDING"], requested: 0))
        #expect(result.accepted == 0)
        #expect(result.declined == 0)
        #expect(result.isEmpty)
    }

    /// The dashboard's document asks for latestReviews, since it needs the
    /// reviewers' names; the same reading has to serve both shapes.
    @Test("The dashboard's review field is read the same way")
    func latestReviewsShape() throws {
        let result = try tally(node(latestReviews: ["APPROVED", "COMMENTED"], requested: 1))
        #expect(result.accepted == 1)
        #expect(result.pending == 1)
    }

    @Test("A pull request with no review fields tallies nothing")
    func missingFields() throws {
        #expect(try tally(node()) == .none)
    }

    @Test("Zero counts are left out of the row")
    func entriesSkipZeroes() {
        let tally = ReviewTally(accepted: 2, declined: 0, pending: 1)
        #expect(tally.entries.map(\.kind) == [.accepted, .pending])
        #expect(tally.entries.map(\.count) == [2, 1])
    }

    @Test("Wording follows the count")
    func wording() {
        #expect(ReviewTallyKind.accepted.sentence(count: 1) == "1 reviewer approved")
        #expect(ReviewTallyKind.accepted.sentence(count: 3) == "3 reviewers approved")
        #expect(ReviewTallyKind.pending.sentence(count: 1) == "1 review still outstanding")
    }
}
