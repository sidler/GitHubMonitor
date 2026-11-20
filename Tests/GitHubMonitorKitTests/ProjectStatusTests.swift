import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Reading a board well enough to move something on it")
struct ProjectBoardReadingTests {
    private let done = ProjectStatus(id: "opt_done", name: "Done", color: .green)

    /// The ids and the columns, out of one `projectItems` answer.
    @Test("The ids and the columns come back with the name")
    func readsIdsAndColumns() {
        let boards = LinkedItemQuery.boards(in: [
            "nodes": [
                [
                    "id": "PVTI_1",
                    "project": [
                        "id": "PVT_1",
                        "title": "SCRUM Board",
                        "field": [
                            "id": "PVTSSF_1",
                            "options": [
                                ["id": "o1", "name": "Open", "color": "GREEN"],
                                ["id": "o2", "name": "In Progress", "color": "YELLOW"],
                            ],
                        ],
                    ],
                    "status": ["name": "Open", "optionId": "o1"],
                ]
            ]
        ])

        #expect(boards.count == 1)
        let board = boards[0]
        #expect(board.label == "SCRUM Board \u{00b7} Open")
        #expect(board.projectID == "PVT_1")
        #expect(board.itemID == "PVTI_1")
        #expect(board.statusFieldID == "PVTSSF_1")
        #expect(board.statuses.map(\.name) == ["Open", "In Progress"])
        #expect(board.statuses.map(\.color) == [.green, .yellow])
        #expect(board.statusOptionID == "o1")
        #expect(board.isSettable)
    }

    /// `read:project` alone names the board and nothing else, so the chip
    /// has to know it cannot offer a menu.
    @Test("A board read without its field cannot be moved")
    func withoutTheField() {
        let boards = LinkedItemQuery.boards(in: [
            "nodes": [["project": ["title": "SCRUM Board"]]]
        ])

        #expect(boards.map(\.title) == ["SCRUM Board"])
        #expect(!boards[0].isSettable)
        #expect(boards[0].statuses.isEmpty)
    }

    /// An issue on a board with no column yet is the one somebody most
    /// wants to move, so the columns must not come from its own value.
    @Test("An item with no column still has columns to offer")
    func noColumnYet() {
        let boards = LinkedItemQuery.boards(in: [
            "nodes": [
                [
                    "id": "PVTI_1",
                    "project": [
                        "id": "PVT_1", "title": "SCRUM Board",
                        "field": ["id": "PVTSSF_1", "options": [["id": "o1", "name": "Open"]]],
                    ],
                ]
            ]
        ])

        #expect(boards[0].status == nil)
        #expect(boards[0].label == "SCRUM Board")
        #expect(boards[0].isSettable)
    }

    @Test("The query asks for the ids only where it may")
    func documentGating() {
        let full = LinkedItemQuery.projectFields(columns: true)
        #expect(full.contains("ProjectV2SingleSelectField"))
        #expect(full.contains("options { id name color }"))
        // The id of the column it is in, which is what ticks the menu
        // and what the chip takes its colour from.
        #expect(full.contains("name optionId"))

        // Without read:org neither the column nor its field is asked for;
        // GitHub refuses the whole query over either.
        let bare = LinkedItemQuery.projectFields(columns: false)
        #expect(!bare.contains("Status"))
        #expect(!bare.contains("options"))
        // The ids of the board itself cost nothing extra and are asked
        // for either way.
        #expect(bare.contains("project { id title"))
    }

    @Test("Moving one board leaves the others where they are")
    func movesOnlyTheOneAsked() {
        let moved = SampleData.board(status: "In Progress")
        let other = SampleData.board(title: "Roadmap", status: "Todo", item: "PVTI_other")

        let after = LinkedProject.after(
            [moved, other], moving: moved.itemID ?? "", to: done
        )

        #expect(after[0].status == "Done")
        #expect(after[1].status == "Todo")
        // The ids survive the move, or the next one would have nothing
        // to go on.
        #expect(after[0].isSettable)
        #expect(after[0].statuses.count == moved.statuses.count)
    }

    /// Two boards read alike often enough -- every team has a "Sprint" --
    /// and moving an issue on one must not move the chip beside it.
    @Test("Two boards of the same name are told apart by the item")
    func byItemNotByTitle() {
        let here = SampleData.board(status: "Todo", item: "PVTI_a")
        let there = SampleData.board(status: "Todo", item: "PVTI_b")

        let after = LinkedProject.after([here, there], moving: "PVTI_b", to: done)

        #expect(after.map(\.status) == ["Todo", "Done"])
    }

    /// A board read without its ids has nothing to match on, so nothing
    /// moves rather than everything.
    @Test("A board with no ids is left alone")
    func unreadableBoard() {
        let bare = LinkedProject(title: "SCRUM Board", status: "Open")

        let after = LinkedProject.after([bare], moving: "", to: done)

        #expect(after[0].status == "Open")
    }
}

@Suite("What the board mutation asks for")
struct ProjectQueryTests {
    @Test("Every id the mutation needs is a variable")
    func takesFourIds() {
        let document = ProjectQuery.document
        #expect(document.contains("updateProjectV2ItemFieldValue"))
        #expect(document.contains("$project: ID!"))
        #expect(document.contains("$item: ID!"))
        #expect(document.contains("$field: ID!"))
        #expect(document.contains("singleSelectOptionId: $option"))
    }

    /// Reading boards is `read:project`; writing one is the whole scope,
    /// and the app must not offer a menu GitHub would refuse.
    @Test("Writing a board is its own scope")
    func writeScope() {
        #expect(ProjectQuery.scope == "project")
        #expect(TokenScopes(granted: ["read:project"]).has(ProjectQuery.scope) == false)
        #expect(TokenScopes(granted: ["project"]).has(LinkedItemQuery.projectScope))
    }

    @Test("The token the app offers to make can move a board")
    func tokenLinkAsksForIt() {
        let link = AccountSettingsView.tokenCreationURL.absoluteString
        #expect(link.contains("project"))
        #expect(!link.contains("read:project"))
    }
}


@Suite("What the settings screen says about a token")
struct TokenScopeListTests {
    /// The screen walks one list, so nothing the app needs can be left
    /// off it by adding a scope to only one of the two.
    @Test("Every scope the app knows about is listed, required ones first")
    func catalogueCoversBoth() {
        let listed = TokenScopes.catalogue.map(\.scope)

        #expect(listed.prefix(TokenScopes.required.count) == TokenScopes.required.map(\.scope)[...])
        #expect(Set(listed) == Set(TokenScopes.required.map(\.scope) + TokenScopes.optional.map(\.scope)))
        #expect(listed.contains("project"))
        #expect(listed.count == Set(listed).count)
    }

    @Test("Each one says what it is for")
    func everyoneHasAPurpose() {
        for entry in TokenScopes.catalogue {
            #expect(!entry.purpose.isEmpty)
            // Read as a row of its own, not as a continuation of the row
            // above it.
            #expect(!entry.purpose.hasPrefix("and "))
        }
    }

    /// The token the app has today reads boards and cannot move anything
    /// on one -- which is exactly what the list has to make visible.
    @Test("A reading token is ticked for what it has and not for the rest")
    func ticksAndCrosses() {
        let scopes = TokenScopes(granted: ["repo", "notifications", "read:org", "read:project"])

        #expect(scopes.isComplete)
        #expect(scopes.has("read:project"))
        #expect(!scopes.has("project"))
        #expect(TokenScopes.catalogue.filter { !scopes.has($0.scope) }.map(\.scope) == ["project"])
    }

    /// A token with the write scope needs no second one for reading.
    @Test("The full project scope ticks the reading one too")
    func writeImpliesRead() {
        let scopes = TokenScopes(granted: ["repo", "notifications", "read:org", "project"])

        #expect(TokenScopes.catalogue.allSatisfy { scopes.has($0.scope) })
    }

    @Test("A missing required scope is still reported as missing")
    func missingRequired() {
        let scopes = TokenScopes(granted: ["notifications"])

        #expect(scopes.missing == ["repo"])
        #expect(!scopes.isComplete)
    }
}


@Suite("What colour a board column is drawn in")
struct ProjectStatusColorTests {
    /// One palette for board columns and issue types, because GitHub
    /// paints both from the same eight under the same names.
    @Test("GitHub's names map onto the app's palette")
    func fromGitHub() {
        #expect(IssueTypeColor(apiValue: "PURPLE") == .purple)
        #expect(IssueTypeColor(apiValue: "CHARTREUSE") == .gray)
        #expect(IssueTypeColor(apiValue: nil) == .gray)
    }

    @Test("The badge takes the colour of the column it is in")
    func badgeColour() {
        let board = SampleData.board(status: "Code Review")
        let review = SampleData.columns.first { $0.name == "Code Review" }

        #expect(board.statusOptionID == review?.id)
        #expect(board.statusColor == .purple)
    }

    /// A move has to carry the id, or the badge keeps the colour of the
    /// column it came from until the next refresh.
    @Test("Moving a board takes its new colour with it")
    func colourFollowsTheMove() {
        let board = SampleData.board(status: "Todo")
        let done = SampleData.columns.first { $0.name == "Done" }!

        let after = board.moved(to: done)

        #expect(after.status == "Done")
        #expect(after.statusOptionID == done.id)
        #expect(after.statusColor == .green)
    }

    /// A board read without its options has a column name and no palette
    /// to look it up in; grey is the honest answer.
    @Test("A column with no palette is grey")
    func noPalette() {
        #expect(LinkedProject(title: "SCRUM Board", status: "Open").statusColor == .gray)
    }

    /// No column at all is not a grey column: the badge has to be able
    /// to say so rather than draw an empty one.
    @Test("No column at all has no colour")
    func noColumn() {
        #expect(LinkedProject(title: "SCRUM Board").statusColor == nil)
    }
}
