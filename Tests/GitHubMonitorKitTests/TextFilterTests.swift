import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("What a filter box means by a match")
struct TextFilterTests {
    @Test("Anywhere in the text, in any case")
    func matchesAnywhere() {
        #expect(TextFilter.keeps("Fix the session filter", matching: "SESSION"))
        #expect(TextFilter.keeps("src/Filter/SessionIdFilter.php", matching: "filter/"))
        #expect(!TextFilter.keeps("Fix the session filter", matching: "cache"))
    }

    @Test("An empty box keeps everything")
    func emptyKeepsAll() {
        #expect(TextFilter.keeps("anything", matching: ""))
        // A stray space is not a search that should empty a list.
        #expect(TextFilter.keeps("anything", matching: "   "))
        #expect(TextFilter.query("   ") == nil)
        #expect(TextFilter.query("  bug ") == "bug")
    }
}

@MainActor
@Suite("A list narrowed by what was typed over it")
struct TitleFilterTests {
    private func state() -> (AppState, SavedList) {
        let app = AppState(settings: Settings(store: TestDefaults.make()))
        let list = SavedList(id: "a", title: "A", query: "is:issue", content: .issues)
        app.listIssues[list.id] = [
            issue("1", title: "Fix the session filter"),
            issue("2", title: "Session cookie expires too soon"),
            issue("3", title: "Bump the linter"),
        ]
        return (app, list)
    }

    private func issue(_ id: String, title: String) -> IssueItem {
        IssueItem(
            id: id, number: 1, title: title, repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            updatedAt: .now
        )
    }

    @Test("Only the titles carrying it are left")
    func narrows() {
        let (app, list) = state()

        app.titleFilter = "session"

        #expect(app.shownIssues(in: list).map(\.id).sorted() == ["1", "2"])
    }

    @Test("The legend counts what the filter left, not what it hid")
    func legendFollows() {
        let (app, list) = state()

        app.titleFilter = "linter"

        #expect(app.issueLegendBase(in: list).map(\.id) == ["3"])
    }

    /// A question asked of the list in front of you, not a setting: it
    /// should not follow you to the next one.
    @Test("Moving on in the sidebar forgets it")
    func forgottenOnMove() {
        let (app, list) = state()
        app.titleFilter = "session"

        app.sidebarSelection = .list(id: list.id, repository: "octo/platform")

        #expect(app.titleFilter.isEmpty)
        #expect(app.shownIssues(in: list).count == 3)
    }
}
