import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Looking up a linked item")
struct LinkedItemQueryTests {
    private func reference(_ number: Int) -> ItemReference {
        ItemReference(repository: "octo/platform", number: number)
    }

    private func reference(in repository: String, _ number: Int) -> ItemReference {
        ItemReference(repository: repository, number: number)
    }

    @Test("Nothing to look up is no request at all")
    func empty() {
        #expect(LinkedItemQuery.document(for: []) == nil)
    }

    /// One request for everything: a lookup costs a point whatever it
    /// carries back, so asking separately would cost once per link.
    @Test("Several numbers in one repository share one block")
    func grouped() throws {
        let document = try #require(
            LinkedItemQuery.document(for: [reference(1), reference(2)])
        )
        #expect(document.components(separatedBy: "repository(owner:").count == 2)
        #expect(document.contains("n1: issueOrPullRequest(number: 1)"))
        #expect(document.contains("n2: issueOrPullRequest(number: 2)"))
    }

    @Test("Two repositories get a block each")
    func twoRepositories() throws {
        let document = try #require(
            LinkedItemQuery.document(for: [reference(1), reference(in: "octo/toolkit", 1)])
        )
        #expect(document.components(separatedBy: "repository(owner:").count == 3)
        #expect(document.contains("\"platform\""))
        #expect(document.contains("\"agp\""))
    }

    /// The same alias twice in one block is rejected by GitHub outright,
    /// which would take the whole panel down with it.
    @Test("The same number twice is asked for once")
    func deduplicated() throws {
        let document = try #require(
            LinkedItemQuery.document(for: [reference(7), reference(7)])
        )
        #expect(document.components(separatedBy: "n7: issueOrPullRequest").count == 2)
    }

    @Test("The budget is asked for alongside")
    func budget() throws {
        let document = try #require(LinkedItemQuery.document(for: [reference(1)]))
        #expect(document.contains("rateLimit"))
    }

    // MARK: - Reading the answer

    private func issueNode(
        number: Int = 1, state: String = "OPEN", reason: String? = nil
    ) -> [String: Any] {
        var node: [String: Any] = [
            "__typename": "Issue",
            "number": number,
            "title": "Something is broken",
            "url": "https://github.com/octo/platform/issues/\(number)",
            "state": state,
            "createdAt": "2026-09-01T10:00:00Z",
            "updatedAt": "2026-09-20T10:00:00Z",
            "body": "It fails on Tuesdays.",
            "repository": ["nameWithOwner": "octo/platform"],
            "author": ["login": "mira"],
            "comments": ["totalCount": 4],
            "labels": ["nodes": [["name": "bug", "color": "d73a4a"]]],
        ]
        if let reason { node["stateReason"] = reason }
        return node
    }

    private func pullRequestNode(state: String = "OPEN", isDraft: Bool = false) -> [String: Any] {
        [
            "__typename": "PullRequest",
            "number": 42,
            "title": "Fix it",
            "url": "https://github.com/octo/platform/pull/42",
            "state": state,
            "isDraft": isDraft,
            "createdAt": "2026-09-01T10:00:00Z",
            "updatedAt": "2026-09-20T10:00:00Z",
            "body": "",
            "repository": ["nameWithOwner": "octo/platform"],
            "author": ["login": "sidler"],
            "comments": ["totalCount": 0],
            "additions": 12,
            "deletions": 3,
            "changedFiles": 2,
            "reviewDecision": "APPROVED",
        ]
    }

    @Test("An issue is read across with its labels and text")
    func issue() throws {
        let payload: [String: Any] = ["r0": ["n1": issueNode()]]
        let states = LinkedItemQuery.summaries(from: payload, asked: [reference(1)])
        guard case .loaded(let summary) = try #require(states[reference(1)]) else {
            Issue.record("expected a summary")
            return
        }
        #expect(summary.kind == .issue)
        #expect(summary.state == .open)
        #expect(summary.title == "Something is broken")
        #expect(summary.comments == 4)
        #expect(summary.labels.map(\.name) == ["bug"])
        #expect(summary.body == "It fails on Tuesdays.")
    }

    /// Closed as done and closed as not planned are different answers, and
    /// the second one means the work is not coming.
    @Test("An issue closed as not planned says so")
    func notPlanned() throws {
        let payload: [String: Any] = [
            "r0": ["n1": issueNode(state: "CLOSED", reason: "NOT_PLANNED")],
        ]
        let states = LinkedItemQuery.summaries(from: payload, asked: [reference(1)])
        guard case .loaded(let summary) = try #require(states[reference(1)]) else { return }
        #expect(summary.state == .notPlanned)
    }

    @Test("An issue closed as done is just closed")
    func closed() throws {
        let payload: [String: Any] = [
            "r0": ["n1": issueNode(state: "CLOSED", reason: "COMPLETED")],
        ]
        let states = LinkedItemQuery.summaries(from: payload, asked: [reference(1)])
        guard case .loaded(let summary) = try #require(states[reference(1)]) else { return }
        #expect(summary.state == .closed)
    }

    @Test(
        "A pull request reports merged, closed, draft or open",
        arguments: [
            ("MERGED", false, LinkedSummary.State.merged),
            ("CLOSED", false, .closed),
            ("OPEN", true, .draft),
            ("OPEN", false, .open),
        ]
    )
    func pullRequestStates(state: String, isDraft: Bool, expected: LinkedSummary.State) throws {
        let payload: [String: Any] = [
            "r0": ["n1": pullRequestNode(state: state, isDraft: isDraft)],
        ]
        let states = LinkedItemQuery.summaries(from: payload, asked: [reference(1)])
        guard case .loaded(let summary) = try #require(states[reference(1)]) else { return }
        #expect(summary.state == expected)
        #expect(summary.kind == .pullRequest)
        #expect(summary.additions == 12)
    }

    /// A number in a sentence need not be an issue at all. Answering
    /// "missing" rather than leaving it out is what stops the panel asking
    /// again for the rest of the session.
    @Test("A number that resolves to nothing is reported as missing")
    func missing() throws {
        let states = LinkedItemQuery.summaries(from: ["r0": [:]], asked: [reference(4711)])
        #expect(states[reference(4711)] == .missing)
    }

    @Test("A repository that answered nothing leaves its numbers missing")
    func repositoryGone() {
        let states = LinkedItemQuery.summaries(from: [:], asked: [reference(1), reference(2)])
        #expect(states[reference(1)] == .missing)
        #expect(states[reference(2)] == .missing)
    }

    /// A transferred issue answers from where it lives now, and that is
    /// where the panel should say it is.
    @Test("The answer's own repository wins over the one asked about")
    func transferred() throws {
        var node = issueNode()
        node["repository"] = ["nameWithOwner": "octo/toolkit"]
        node["number"] = 9
        let states = LinkedItemQuery.summaries(from: ["r0": ["n1": node]], asked: [reference(1)])
        guard case .loaded(let summary) = try #require(states[reference(1)]) else { return }
        #expect(summary.reference == ItemReference(repository: "octo/toolkit", number: 9))
    }
}
