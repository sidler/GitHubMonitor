import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Reading which files are ticked off")
struct ViewedFilesQueryTests {
    private func payload(
        _ nodes: [[String: Any]], next: String? = nil
    ) -> [String: Any] {
        [
            "node": [
                "files": [
                    "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any],
                    "nodes": nodes,
                ],
            ],
        ]
    }

    /// GitHub's three answers, not two. `DISMISSED` is the one that must
    /// not be flattened into "not viewed": it means the file changed after
    /// it was ticked, which is the file most worth reading again.
    @Test(
        "All three states are read across",
        arguments: [
            ("VIEWED", FileViewedState.viewed),
            ("UNVIEWED", .unviewed),
            ("DISMISSED", .dismissed),
        ]
    )
    func states(raw: String, expected: FileViewedState) {
        let page = ViewedFilesQuery.page(
            from: payload([["path": "a.swift", "viewerViewedState": raw]])
        )
        #expect(page.states["a.swift"] == expected)
    }

    /// A state this app does not know is not a tick.
    @Test("An unfamiliar answer counts as not viewed")
    func unknown() {
        #expect(FileViewedState(apiValue: "SOMETHING_NEW") == .unviewed)
        #expect(FileViewedState(apiValue: nil) == .unviewed)
    }

    @Test("Only a plain tick folds the patch away")
    func folding() {
        #expect(FileViewedState.viewed.isFolded)
        #expect(!FileViewedState.unviewed.isFolded)
        // The whole point of the state: it needs reading, so it stays open.
        #expect(!FileViewedState.dismissed.isFolded)
    }

    @Test("A page says where to carry on, and the last one does not")
    func paging() {
        let more = ViewedFilesQuery.page(
            from: payload([["path": "a", "viewerViewedState": "VIEWED"]], next: "cursor-1")
        )
        #expect(more.cursor == "cursor-1")
        #expect(ViewedFilesQuery.page(from: payload([])).cursor == nil)
    }

    @Test("An answer that is not a pull request is empty, not a crash")
    func notAPullRequest() {
        #expect(ViewedFilesQuery.page(from: ["node": [:]]).states.isEmpty)
        #expect(ViewedFilesQuery.page(from: [:]).states.isEmpty)
    }

    /// Both mutations exist and differ; sending the wrong one would tick a
    /// file the reviewer just untucked.
    @Test("Setting and clearing are different mutations")
    func mutations() {
        #expect(ViewedFilesQuery.document(setting: true).contains("markFileAsViewed"))
        #expect(ViewedFilesQuery.document(setting: false).contains("unmarkFileAsViewed"))
        #expect(!ViewedFilesQuery.document(setting: true).contains("unmarkFileAsViewed"))
    }

    @Test("The query asks for the page and the budget")
    func document() {
        #expect(ViewedFilesQuery.document.contains("viewerViewedState"))
        #expect(ViewedFilesQuery.document.contains("rateLimit"))
        #expect(ViewedFilesQuery.document.contains("$after"))
    }
}

@MainActor
@Suite("What the diff makes of the ticks")
struct ViewedFilesStateTests {
    private func state() -> AppState {
        AppState(settings: Settings(store: TestDefaults.make()))
    }

    private func file(_ path: String) -> ChangedFile {
        ChangedFile(path: path, additions: 1, deletions: 0, change: .modified, patch: "@@")
    }

    @Test("A file nobody has ticked is not viewed")
    func unknownFile() {
        #expect(state().viewedState(of: "a.swift", in: "pr-1") == .unviewed)
    }

    @Test("The ticks are kept apart per pull request")
    func perPullRequest() {
        let state = state()
        state.viewedFiles["pr-1"] = ["a.swift": .viewed]
        #expect(state.viewedState(of: "a.swift", in: "pr-1") == .viewed)
        #expect(state.viewedState(of: "a.swift", in: "pr-2") == .unviewed)
    }

    /// The header says "n of m viewed", and a file changed since it was
    /// ticked is not one of the n -- it is waiting to be read again.
    @Test("Only plain ticks count towards the progress")
    func progress() {
        let state = state()
        let files = [file("a"), file("b"), file("c")]
        state.viewedFiles["pr-1"] = ["a": .viewed, "b": .dismissed]
        #expect(state.viewedCount(of: files, in: "pr-1") == 1)
    }

    /// Counted over the files on screen, so it cannot claim more than it
    /// shows when the patch list was cut short at the cap.
    @Test("Progress counts the files shown, not the ticks held")
    func progressIsBounded() {
        let state = state()
        state.viewedFiles["pr-1"] = ["a": .viewed, "gone.swift": .viewed]
        #expect(state.viewedCount(of: [file("a")], in: "pr-1") == 1)
    }
}

@Suite("The changelog the app shows")
struct ChangelogTests {
    /// The file the app ships is the file in the repository; a second copy
    /// written out in Swift would be the one that goes stale.
    @Test("The repository's changelog names the released versions")
    func repositoryFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GitHubMonitorKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("CHANGELOG.md")
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(text.contains("## 1.1.0"))
        #expect(text.contains("## 0.1.0"))
        // Newest first, which is what the window title relies on. The
        // "Unreleased" heading above them is not a version and is skipped.
        #expect(Changelog.newestVersion(in: text) == "1.1.0")
    }

    @Test("The newest version is the first heading, whatever follows it")
    func newest() {
        #expect(Changelog.newestVersion(in: "# Changelog\n\n## 2.0\n\ntext\n\n## 1.0") == "2.0")
        #expect(Changelog.newestVersion(in: "# Changelog\n\nno versions yet") == nil)
        #expect(Changelog.newestVersion(in: "") == nil)
        // A heading that is not a version number is not a version.
        #expect(Changelog.newestVersion(in: "## Unreleased\n\n## 3.2.1") == "3.2.1")
    }

    /// A build that forgot to copy the file should say so rather than open
    /// an empty window.
    @Test("A bundle without one says so")
    func missing() {
        let text = Changelog.text(in: Bundle(for: TestAnchor.self))
        #expect(text.contains("does not carry one"))
    }
}

/// Only here to name a bundle that has no changelog in it.
private final class TestAnchor {}
