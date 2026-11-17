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
        #expect(document.contains("\"toolkit\""))
    }

    /// The bug this replaced: everything past the cap was recorded as
    /// "not there" without ever having been asked about, and a genuinely
    /// linked issue vanished from the pane for the rest of the run.
    @Test("More than one request's worth is split, not dropped")
    func batched() {
        let many = (1...(LinkedItemQuery.maximumLookups + 3)).map { reference($0) }
        let batches = LinkedItemQuery.batches(many)

        #expect(batches.count == 2)
        #expect(batches[0].count == LinkedItemQuery.maximumLookups)
        #expect(batches[1].count == 3)
        // Every reference asked for lands in exactly one batch.
        #expect(batches.flatMap { $0 } == many)
    }

    @Test("A batch repeats nothing, even across the split")
    func batchesDeduplicate() {
        let batches = LinkedItemQuery.batches([reference(1), reference(1), reference(2)])
        #expect(batches == [[reference(1), reference(2)]])
    }

    @Test("Nothing to ask about is no batches at all")
    func noBatches() {
        #expect(LinkedItemQuery.batches([]).isEmpty)
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
            "author": ["login": "avery"],
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

/// Who a linked ticket is on.
///
/// The panel's first question is what this is about; its second is who is
/// on it, and that one had no answer at all -- the field was never asked
/// for. It is asked for on both kinds: a pull request carries an assignee
/// as often as an issue does, and the panel draws them with one view.
@Suite("Who a linked item is assigned to")
struct LinkedAssigneeTests {
    private let reference = ItemReference(repository: "octo/platform", number: 1)

    private func node(_ assignees: [String]?, isPullRequest: Bool = false) -> [String: Any] {
        var node: [String: Any] = [
            "__typename": isPullRequest ? "PullRequest" : "Issue",
            "number": 1,
            "title": "Something is broken",
            "url": "https://github.com/octo/platform/issues/1",
            "state": "OPEN",
            "createdAt": "2026-09-01T10:00:00Z",
            "updatedAt": "2026-09-20T10:00:00Z",
            "repository": ["nameWithOwner": "octo/platform"],
            "author": ["login": "avery"],
        ]
        if let assignees {
            node["assignees"] = ["nodes": assignees.map { ["login": $0] }]
        }
        return node
    }

    private func summary(_ node: [String: Any]) throws -> LinkedSummary {
        let states = LinkedItemQuery.summaries(from: ["r0": ["n1": node]], asked: [reference])
        guard case .loaded(let summary) = try #require(states[reference]) else {
            Issue.record("expected a summary")
            throw CancellationError()
        }
        return summary
    }

    @Test("The document asks for them on issues and on pull requests")
    func asked() throws {
        let document = try #require(LinkedItemQuery.document(for: [reference]))

        #expect(document.components(separatedBy: "assignees(first:").count == 3)
    }

    @Test("Everyone named comes across, in the order GitHub gave them")
    func several() throws {
        #expect(try summary(node(["avery", "mrick808"])).assignees == ["avery", "mrick808"])
    }

    @Test("A pull request's assignees are read too")
    func pullRequest() throws {
        #expect(try summary(node(["avery"], isPullRequest: true)).assignees == ["avery"])
    }

    /// Nobody assigned and the field missing are the same answer here, and
    /// the panel says "unassigned" for both. A field that is absent is one
    /// GitHub would not hand over, which is not a different fact about the
    /// ticket.
    @Test("Nobody on it is an empty list, not a crash")
    func nobody() throws {
        #expect(try summary(node([])).assignees.isEmpty)
        #expect(try summary(node(nil)).assignees.isEmpty)
    }
}

/// The boards a linked ticket sits on.
///
/// Asked for only where the token can see them. ProjectsV2 is behind a
/// scope of its own, and a classic token granted `repo` alone does not
/// carry it -- GitHub answers a query that asks anyway by refusing the
/// whole thing, so the panel would stop showing linked tickets at all
/// rather than merely showing no board.
@Suite("The boards a linked item sits on")
struct LinkedProjectTests {
    private let reference = ItemReference(repository: "octo/platform", number: 1)

    private func node(_ items: [[String: Any]]?) -> [String: Any] {
        var node: [String: Any] = [
            "__typename": "Issue",
            "number": 1,
            "title": "Something is broken",
            "url": "https://github.com/octo/platform/issues/1",
            "state": "OPEN",
            "createdAt": "2026-09-01T10:00:00Z",
            "updatedAt": "2026-09-20T10:00:00Z",
            "repository": ["nameWithOwner": "octo/platform"],
            "author": ["login": "avery"],
        ]
        if let items { node["projectItems"] = ["nodes": items] }
        return node
    }

    private func summary(_ node: [String: Any]) throws -> LinkedSummary {
        let states = LinkedItemQuery.summaries(from: ["r0": ["n1": node]], asked: [reference])
        guard case .loaded(let summary) = try #require(states[reference]) else {
            Issue.record("expected a summary")
            throw CancellationError()
        }
        return summary
    }

    /// The rule the whole feature hangs on.
    @Test("Without the scope the query does not mention boards at all")
    func notAsked() throws {
        let document = try #require(LinkedItemQuery.document(for: [reference]))

        #expect(!document.contains("projectItems"))
    }

    @Test("With the scope both kinds are asked")
    func asked() throws {
        let document = try #require(
            LinkedItemQuery.document(for: [reference], projects: true, columns: true)
        )

        #expect(document.components(separatedBy: "projectItems(first:").count == 3)
        // By name, because a board's fields can be in any order.
        #expect(document.contains(#"fieldValueByName(name: "Status")"#))
    }

    /// The second tier, and the reason it exists. A board's columns are a
    /// field of the project, and reading what an organisation's field is
    /// called needs the organisation's own scope -- GitHub refused the
    /// whole query over it, naming `name` rather than `projectItems`, so
    /// the token that can see boards but not that still gets the boards.
    @Test("Without the column scope the board is named and the column is not")
    func boardWithoutColumn() throws {
        let document = try #require(
            LinkedItemQuery.document(for: [reference], projects: true)
        )

        #expect(document.contains("projectItems(first:"))
        #expect(!document.contains("fieldValueByName"))
    }

    @Test("A board is read with the column the item is in")
    func withStatus() throws {
        let read = try summary(node([
            ["project": ["title": "Sprint 42"], "status": ["name": "In Review"]],
        ]))

        #expect(read.projects == [LinkedProject(title: "Sprint 42", status: "In Review")])
        #expect(read.projects.first?.label == "Sprint 42 \u{00b7} In Review")
    }

    /// Not every board has a Status field, and being on one is an answer
    /// even without a column.
    @Test("A board without a Status field is still named")
    func withoutStatus() throws {
        let read = try summary(node([["project": ["title": "Roadmap"]]]))

        #expect(read.projects == [LinkedProject(title: "Roadmap")])
        #expect(read.projects.first?.label == "Roadmap")
    }

    /// An item on a board the token may not read comes back with a null
    /// project, which is nothing to draw rather than something to crash on.
    @Test("A board that cannot be read is left out")
    func unreadable() throws {
        let read = try summary(node([
            ["project": NSNull(), "status": NSNull()],
            ["project": ["title": "Sprint 42"]],
        ]))

        #expect(read.projects.map(\.title) == ["Sprint 42"])
    }

    @Test("On no board at all is an empty list")
    func none() throws {
        #expect(try summary(node([])).projects.isEmpty)
        #expect(try summary(node(nil)).projects.isEmpty)
    }
}

/// The scope itself: GitHub reports only the broadest one granted.
@Suite("A token that may read boards")
struct ProjectScopeTests {
    @Test("The read-only scope is the one that counts")
    func readOnly() {
        #expect(TokenScopes(header: "repo, read:project").has(LinkedItemQuery.projectScope))
    }

    /// Somebody who granted the writable scope has the readable one, and
    /// GitHub will not list both.
    @Test("The writable scope covers it")
    func writable() {
        #expect(TokenScopes(header: "repo, project").has(LinkedItemQuery.projectScope))
    }

    @Test("What the app asks for at sign-in does not cover it")
    func plain() {
        #expect(!TokenScopes(header: "repo, notifications").has(LinkedItemQuery.projectScope))
    }

    /// The scope the columns need is a different one, and a token can
    /// carry either without the other.
    @Test("Seeing boards is not seeing their columns")
    func columns() {
        let boardsOnly = TokenScopes(header: "repo, notifications, read:project")
        #expect(boardsOnly.has(LinkedItemQuery.projectScope))
        #expect(!boardsOnly.has(LinkedItemQuery.columnScope))

        let both = TokenScopes(header: "repo, notifications, read:project, admin:org")
        #expect(both.has(LinkedItemQuery.columnScope))
    }
}
