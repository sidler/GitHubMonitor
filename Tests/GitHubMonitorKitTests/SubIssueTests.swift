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
