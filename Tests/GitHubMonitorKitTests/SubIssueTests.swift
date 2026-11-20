import Foundation
import Testing

@testable import GitHubMonitorKit

/// The issues filed under another one, and how far through them it is.
@Suite("Sub-issues")
struct SubIssueTests {
    private func child(
        _ number: Int,
        state: String = "OPEN",
        reason: String? = nil,
        repository: String = "octo/platform",
        type: [String: Any]? = nil
    ) -> [String: Any] {
        var node: [String: Any] = [
            "number": number,
            "title": "Child \(number)",
            "url": "https://github.com/\(repository)/issues/\(number)",
            "state": state,
            "repository": ["nameWithOwner": repository],
        ]
        if let reason { node["stateReason"] = reason }
        if let type { node["issueType"] = type }
        return node
    }

    private func detail(
        total: Int,
        completed: Int,
        children: [[String: Any]]
    ) throws -> IssueDetail {
        try IssueQuery.detail(from: [
            "node": [
                "body": "",
                "subIssuesSummary": ["total": total, "completed": completed],
                "subIssues": ["nodes": children],
                "comments": ["totalCount": 0, "nodes": []],
            ]
        ])
    }

    @Test("The children are read with their number, title and state")
    func reads() throws {
        let read = try detail(
            total: 3,
            completed: 2,
            children: [
                child(11, state: "CLOSED"),
                child(12, state: "CLOSED", reason: "NOT_PLANNED"),
                child(13, type: ["name": "Bug", "color": "RED"]),
            ]
        )

        #expect(read.subIssues.map(\.number) == [11, 12, 13])
        #expect(read.subIssues[0].state == .closed)
        // Dropped is not done, whatever the count says, and the row has to
        // be able to show which it was.
        #expect(read.subIssues[1].state == .notPlanned)
        #expect(read.subIssues[2].state == .open)
        #expect(read.subIssues[2].type?.name == "Bug")
        #expect(read.subIssues[2].type?.color == .red)
        #expect(read.subIssues[0].title == "Child 11")
    }

    /// A child can live in another repository, and the row says so only
    /// when it does.
    @Test("A child from another repository keeps its own name")
    func elsewhere() throws {
        let read = try detail(
            total: 1,
            completed: 0,
            children: [child(7, repository: "octo/tools")]
        )

        #expect(read.subIssues.first?.repository == "octo/tools")
        #expect(read.subIssues.first?.id == "octo/tools#7")
    }

    /// Most issues have none, and a bar at nought out of nought says
    /// nothing worth the room.
    @Test("An issue with no children has no progress")
    func none() throws {
        let read = try IssueQuery.detail(from: [
            "node": ["body": "", "comments": ["totalCount": 0, "nodes": []]]
        ])

        #expect(read.progress == nil)
        #expect(read.subIssues.isEmpty)
        #expect(read.unlistedSubIssues == 0)
    }

    @Test("An issue whose summary counts nothing has no progress either")
    func emptySummary() throws {
        let read = try detail(total: 0, completed: 0, children: [])

        #expect(read.progress == nil)
    }

    /// The count comes from GitHub's summary, not from the rows: the rows
    /// stop at a limit and the summary does not, so an issue with sixty
    /// children would otherwise report progress through the first fifty.
    @Test("The progress is counted over all the children, not the listed ones")
    func countsBeyondTheList() throws {
        let read = try detail(
            total: 60,
            completed: 40,
            children: (1...50).map { child($0, state: "CLOSED") }
        )

        #expect(read.progress?.total == 60)
        #expect(read.progress?.completed == 40)
        #expect(read.subIssues.count == 50)
        // And the pane has to be able to say the list is cut.
        #expect(read.unlistedSubIssues == 10)
    }

    @Test("The progress reads as a count and a fraction")
    func arithmetic() {
        let progress = SubIssueProgress(total: 11, completed: 6)

        #expect(progress.summary == "6 of 11 done")
        #expect(progress.remaining == 5)
        #expect(progress.isFinished == false)
        #expect(progress.fraction == 6.0 / 11.0)

        #expect(SubIssueProgress(total: 3, completed: 3).isFinished)
        #expect(SubIssueProgress(total: 0, completed: 0).fraction == nil)
        #expect(SubIssueProgress(total: 0, completed: 0).isFinished == false)
    }

    /// However the two numbers were counted, a bar past its own end is a
    /// drawing bug rather than news.
    @Test("More done than there are is clamped")
    func clamps() {
        let progress = SubIssueProgress(total: 2, completed: 5)

        #expect(progress.completed == 2)
        #expect(progress.fraction == 1)
        #expect(progress.remaining == 0)
    }

    /// The pane writes a label change into the detail before GitHub has
    /// agreed to it, and every field it forgets to carry over vanishes
    /// from the screen at that moment.
    @Test("Changing a label keeps the children on screen")
    func survivesALabelChange() throws {
        let read = try detail(total: 2, completed: 1, children: [child(1), child(2)])
        let after = read.withLabels([IssueLabel(name: "bug", color: "ff0000")])

        #expect(after.subIssues.count == 2)
        #expect(after.progress == read.progress)
    }

    /// An issue is far more likely to be somebody's sub-task than to have
    /// sub-tasks of its own, so the pane says what it is part of.
    @Test("The issue a child is filed under is read too")
    func parent() throws {
        let read = try IssueQuery.detail(from: [
            "node": [
                "body": "",
                "parent": [
                    "number": 33778,
                    "title": "LBBW VVT",
                    "url": "https://github.com/octo/platform/issues/33778",
                    "state": "OPEN",
                    "repository": ["nameWithOwner": "octo/platform"],
                    "issueType": ["name": "Epic", "color": "PURPLE"],
                ],
                "comments": ["totalCount": 0, "nodes": []],
            ]
        ])

        #expect(read.parent?.number == 33778)
        #expect(read.parent?.title == "LBBW VVT")
        #expect(read.parent?.state == .open)
        #expect(read.parent?.type?.name == "Epic")
    }

    @Test("An issue under nothing has no parent")
    func orphan() throws {
        let read = try IssueQuery.detail(from: [
            "node": ["body": "", "comments": ["totalCount": 0, "nodes": []]]
        ])

        #expect(read.parent == nil)
    }

    /// The panel that previews a linked pull request is the one a
    /// sub-issue opens, so a child has to be something it can look up.
    @Test("A related issue can be handed to the preview panel")
    func previewLink() {
        let child = RelatedIssue(
            number: 42, title: "Connector", repository: "octo/tools",
            url: URL(string: "https://github.com/octo/tools/issues/42")!, state: .closed
        )

        #expect(child.link.reference == ItemReference(repository: "octo/tools", number: 42))
        #expect(child.link.title == "Connector")
        #expect(child.link.state == .closed)
        // The strong kind: GitHub records this relation rather than it
        // being a number read out of a sentence.
        #expect(child.link.kind == .closes)
    }

    /// A closed child is a done child, whichever way it was closed, because
    /// that is how GitHub counts the summary beside it.
    @Test("Open and closed are told apart")
    func doneness() {
        func made(_ state: LinkedSummary.State) -> RelatedIssue {
            RelatedIssue(
                number: 1, title: "t", repository: "octo/platform",
                url: URL(string: "https://github.com")!, state: state
            )
        }

        #expect(made(.open).isClosed == false)
        #expect(made(.closed).isClosed)
        #expect(made(.notPlanned).isClosed)
    }
}

/// What the pane about an issue says about the issue.
///
/// The three facts somebody opens a ticket for -- where it stands, who is
/// on it, which board it is on -- were in the fold a pull request draws
/// for a ticket it links to, and in no form at all in the pane about the
/// ticket itself. Same facts, same view; these are about the detail query
/// learning to ask for them.
@Suite("An issue's own state, assignee and board")
struct IssueDetailFactsTests {
    private func detail(_ node: [String: Any]) throws -> IssueDetail {
        try IssueQuery.detail(from: ["node": node])
    }

    @Test("Where it stands comes across, including closed as not planned")
    func state() throws {
        #expect(try detail(["body": ""]).state == .open)
        #expect(try detail(["body": "", "state": "CLOSED"]).state == .closed)
        #expect(
            try detail(["body": "", "state": "CLOSED", "stateReason": "NOT_PLANNED"]).state
                == .notPlanned
        )
    }

    @Test("Everyone on it comes across, and nobody is an empty list")
    func assignees() throws {
        let node: [String: Any] = [
            "body": "",
            "assignees": ["nodes": [["login": "avery"], ["login": "mrick808"]]],
        ]
        #expect(try detail(node).assignees == ["avery", "mrick808"])
        #expect(try detail(["body": ""]).assignees.isEmpty)
    }

    @Test("The board and its column come across")
    func boards() throws {
        let node: [String: Any] = [
            "body": "",
            "projectItems": [
                "nodes": [["project": ["title": "SCRUM Board"], "status": ["name": "Code Review"]]],
            ],
        ]
        #expect(try detail(node).projects.first?.label == "SCRUM Board \u{00b7} Code Review")
    }

    /// The same two-tier rule the linked lookup follows, and for the same
    /// reason: GitHub refuses the whole query over a field the token
    /// cannot see, which would cost this pane its text and its thread.
    @Test("Boards and columns are asked for only where the token may read them")
    func scopes() {
        let none = IssueQuery.detailDocument(projects: false, columns: false)
        #expect(!none.contains("projectItems"))
        #expect(!none.contains("fieldValueByName"))

        let boards = IssueQuery.detailDocument(projects: true, columns: false)
        #expect(boards.contains("projectItems"))
        #expect(!boards.contains("fieldValueByName"))

        let both = IssueQuery.detailDocument(projects: true, columns: true)
        #expect(both.contains("fieldValueByName"))
    }

    /// Asked for unconditionally, because neither costs a scope the app
    /// does not already require.
    @Test("The state and the assignees are always asked for")
    func alwaysAsked() {
        let document = IssueQuery.detailDocument(projects: false, columns: false)
        #expect(document.contains("stateReason"))
        #expect(document.contains("assignees(first:"))
    }
}

/// The sample carries these facts, so the panes that draw them can be
/// looked at without a token and without a request.
///
/// Three shapes between the two sample issues, which is what the drawing
/// has to cope with: one assignee and a board with a column, two
/// assignees and a board without one, and an issue that is closed rather
/// than open.
@MainActor
@Suite("The sample has a state, an assignee and a board")
struct SampleTicketFactsTests {
    @Test("The epic is open, on somebody, and in a column")
    func epic() {
        let detail = SampleData.epicDetail()

        #expect(detail.state == .open)
        #expect(detail.assignees == ["noor"])
        #expect(detail.projects.first?.label == "Platform Board \u{00b7} In Progress")
    }

    /// A board with no Status field, two people on it, and over.
    @Test("The child is closed, on two people, and on a board without a column")
    func child() {
        let detail = SampleData.childDetail()

        #expect(detail.state == .closed)
        #expect(detail.assignees == ["arun", "mira"])
        #expect(detail.projects.first?.label == "Roadmap")
        // And a second board beside it, which is the case the chips wrap
        // for: a ticket sits on the team's board and on the roadmap.
        #expect(detail.projects.count == 2)
        #expect(detail.projects.last?.label == "Platform Board \u{00b7} Code Review")
    }

    /// And the fold a pull request draws for a ticket it links to, which
    /// is the other pane the same view serves.
    @Test("A linked issue carries them too")
    func linked() throws {
        let summaries = SampleData.linkedSummaries()
        guard case .loaded(let summary) = try #require(summaries.values.first(where: {
            if case .loaded(let found) = $0 { return found.kind == .issue }
            return false
        })) else { return }

        #expect(!summary.assignees.isEmpty)
        #expect(summary.projects.first?.status == "Code Review")
    }
}
