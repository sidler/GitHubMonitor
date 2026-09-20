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
        let items = PullRequestParser.pullRequests(from: ["s0": ["nodes": [node(id: "a")]]])
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
            "s0": ["nodes": [node(id: "same"), node(id: "only-personal")]],
            "s1": ["nodes": [node(id: "same"), node(id: "only-team")]],
        ]
        let items = PullRequestParser.pullRequests(from: payload)
        #expect(items.count == 3)
        #expect(Set(items.map(\.id)) == ["same", "only-personal", "only-team"])
    }

    @Test("Results are sorted with the most recently updated first")
    func sorting() {
        let payload: [String: Any] = ["s0": ["nodes": [
            node(id: "old", updated: "2026-09-01T10:00:00Z"),
            node(id: "new", updated: "2026-09-19T10:00:00Z"),
        ]]]
        #expect(PullRequestParser.pullRequests(from: payload).map(\.id) == ["new", "old"])
    }

    /// Search results also contain issues, which arrive as empty objects
    /// because the fragment only matches pull requests.
    @Test("Non-pull-request hits are skipped")
    func skipsUnusableNodes() {
        let payload: [String: Any] = ["s0": ["nodes": [[:], node(id: "real")]]]
        let items = PullRequestParser.pullRequests(from: payload)
        #expect(items.map(\.id) == ["real"])
    }

    @Test("A deleted author does not drop the pull request")
    func missingAuthor() throws {
        var raw = node(id: "a")
        raw["author"] = NSNull()
        let items = PullRequestParser.pullRequests(from: ["s0": ["nodes": [raw]]])
        let item = try #require(items.first)
        #expect(item.author == "ghost")
        #expect(item.authorAvatarURL == nil)
    }

    @Test("Absent review decision and checks degrade to 'none'")
    func absentOptionalFields() throws {
        let items = PullRequestParser.pullRequests(
            from: ["s0": ["nodes": [node(id: "a", decision: nil, rollup: nil)]]]
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
        let items = PullRequestParser.pullRequests(from: ["s0": ["nodes": [node(id: "a", rollup: raw)]]])
        #expect(try #require(items.first).checks == expected)
    }

    @Test("An empty payload yields no items")
    func emptyPayload() {
        #expect(PullRequestParser.pullRequests(from: [:]).isEmpty)
        #expect(PullRequestParser.pullRequests(from: ["s0": ["nodes": []]]).isEmpty)
    }
}
