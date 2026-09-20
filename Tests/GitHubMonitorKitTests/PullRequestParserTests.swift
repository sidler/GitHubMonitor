import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Pull request parser")
struct PullRequestParserTests {
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

    @Test("Fields are mapped across")
    func mapping() throws {
        let items = PullRequestParser.pullRequests(from: ["r0": ["nodes": [node(id: "a")]]], group: .reviewRequested)
        let item = try #require(items.first)
        #expect(item.number == 7)
        #expect(item.repository == "octo/server")
        #expect(item.author == "mira")
        #expect(item.authorAvatarURL?.absoluteString == "https://example.com/a.png")
        #expect(item.reviewDecision == .reviewRequired)
        #expect(item.checks == .success)
    }

    /// A pull request requested from the user personally and from one of their
    /// teams appears in both searches; counting it twice would inflate the
    /// menu bar badge.
    @Test("The same pull request in two searches is counted once")
    func deduplication() {
        let payload: [String: Any] = [
            "r0": ["nodes": [node(id: "same"), node(id: "only-personal")]],
            "r1": ["nodes": [node(id: "same"), node(id: "only-team")]],
        ]
        let items = PullRequestParser.pullRequests(from: payload, group: .reviewRequested)
        #expect(items.count == 3)
        #expect(Set(items.map(\.id)) == ["same", "only-personal", "only-team"])
    }

    @Test("Results are sorted with the most recently updated first")
    func sorting() {
        let payload: [String: Any] = ["r0": ["nodes": [
            node(id: "old", updated: "2026-09-01T10:00:00Z"),
            node(id: "new", updated: "2026-09-19T10:00:00Z"),
        ]]]
        #expect(PullRequestParser.pullRequests(from: payload, group: .reviewRequested).map(\.id) == ["new", "old"])
    }

    /// Search results also contain issues, which arrive as empty objects
    /// because the fragment only matches pull requests.
    @Test("Non-pull-request hits are skipped")
    func skipsUnusableNodes() {
        let payload: [String: Any] = ["r0": ["nodes": [[:], node(id: "real")]]]
        let items = PullRequestParser.pullRequests(from: payload, group: .reviewRequested)
        #expect(items.map(\.id) == ["real"])
    }

    @Test("A deleted author does not drop the pull request")
    func missingAuthor() throws {
        var raw = node(id: "a")
        raw["author"] = NSNull()
        let items = PullRequestParser.pullRequests(from: ["r0": ["nodes": [raw]]], group: .reviewRequested)
        let item = try #require(items.first)
        #expect(item.author == "ghost")
        #expect(item.authorAvatarURL == nil)
    }

    @Test("Absent review decision and checks degrade to 'none'")
    func absentOptionalFields() throws {
        let items = PullRequestParser.pullRequests(
            from: ["r0": ["nodes": [node(id: "a", decision: nil, rollup: nil)]]],
            group: .reviewRequested
        )
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
        let items = PullRequestParser.pullRequests(from: ["r0": ["nodes": [node(id: "a", rollup: raw)]]], group: .reviewRequested)
        #expect(try #require(items.first).checks == expected)
    }

    /// One document carries both lists; a parser that ignored the alias
    /// prefix would show the user's own pull requests in the review queue.
    @Test("Groups are kept apart by their alias prefix")
    func groupsAreSeparate() {
        let payload: [String: Any] = [
            "r0": ["nodes": [node(id: "to-review")]],
            "a0": ["nodes": [node(id: "mine")]],
        ]
        #expect(PullRequestParser.pullRequests(from: payload, group: .reviewRequested).map(\.id) == ["to-review"])
        #expect(PullRequestParser.pullRequests(from: payload, group: .authored).map(\.id) == ["mine"])
    }

    @Test("An empty payload yields no items")
    func emptyPayload() {
        #expect(PullRequestParser.pullRequests(from: [:], group: .reviewRequested).isEmpty)
        #expect(PullRequestParser.pullRequests(from: ["r0": ["nodes": []]], group: .reviewRequested).isEmpty)
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
