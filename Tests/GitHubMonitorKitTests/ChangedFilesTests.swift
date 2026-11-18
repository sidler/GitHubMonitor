import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("The files a pull request touches")
struct ChangedFilesTests {
    private func payload(_ files: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: files)
    }

    private func file(
        _ path: String, additions: Int, deletions: Int,
        status: String = "modified", patch: String? = "@@ -1 +1 @@"
    ) -> [String: Any] {
        var node: [String: Any] = [
            "filename": path, "additions": additions, "deletions": deletions, "status": status,
        ]
        if let patch { node["patch"] = patch }
        return node
    }

    /// In a narrow pane the useful question is where the work is, so the
    /// file with four hundred changed lines does not make anyone scroll.
    ///
    /// By path, not by size: the list in the pane is a way into the diff,
    /// and the tree beside the diff is in path order. A list you navigate
    /// by has to match the thing it navigates.
    ///
    /// Ordered over the whole set rather than page by page, or the second
    /// page would start over at the top of the alphabet.
    @Test("Files come in path order, whatever their size")
    func order() throws {
        let files = try ChangedFilesQuery.ordered(ChangedFilesQuery.files(from: payload([
            file("src/small.php", additions: 1, deletions: 0),
            file("README.md", additions: 300, deletions: 100),
            file("src/Filter/middle.php", additions: 10, deletions: 10),
        ])))
        #expect(files.map(\.path) == ["README.md", "src/Filter/middle.php", "src/small.php"])
    }

    /// The same order the tree beside the diff puts them in, so the two
    /// cannot drift apart.
    @Test("It is the order the diff itself uses")
    func matchesTheDiff() throws {
        let read = try ChangedFilesQuery.files(from: payload([
            file("b/x.php", additions: 2, deletions: 0),
            file("a/y.php", additions: 400, deletions: 1),
            file("a/x.php", additions: 1, deletions: 1),
        ]))
        #expect(
            ChangedFilesQuery.ordered(read).map(\.path)
                == OpenedDiff.alphabetical(read).map(\.path)
        )
    }

    /// GitHub sends no patch for a binary file or one it judged too large.
    @Test("A file without a patch is still a file")
    func noPatch() throws {
        let files = try ChangedFilesQuery.files(from: payload([
            file("logo.png", additions: 0, deletions: 0, status: "added", patch: nil),
        ]))
        #expect(files.count == 1)
        #expect(files.first?.patch == nil)
        #expect(files.first?.change == .added)
    }

    /// The name a conversation on the file's removed lines is filed
    /// under. Without it such a remark matches no file in the diff.
    @Test("A renamed file keeps the name it had")
    func renamed() throws {
        var node = file("src/New/Thing.php", additions: 1, deletions: 2, status: "renamed")
        node["previous_filename"] = "src/Old/Thing.php"
        let files = try ChangedFilesQuery.files(from: payload([node]))
        #expect(files.first?.previousPath == "src/Old/Thing.php")
        #expect(files.first?.change == .renamed)
    }

    @Test("A file that was not moved has no previous name")
    func notRenamed() throws {
        let files = try ChangedFilesQuery.files(
            from: payload([file("src/Thing.php", additions: 1, deletions: 1)])
        )
        #expect(files.first?.previousPath == nil)
    }

    @Test("Every status GitHub sends maps to something sayable")
    func statuses() {
        #expect(ChangedFile.Change(apiValue: "added") == .added)
        #expect(ChangedFile.Change(apiValue: "copied") == .added)
        #expect(ChangedFile.Change(apiValue: "changed") == .modified)
        #expect(ChangedFile.Change(apiValue: "removed") == .removed)
        #expect(ChangedFile.Change(apiValue: "renamed") == .renamed)
        #expect(ChangedFile.Change(apiValue: "unmerged") == .other)
        #expect(ChangedFile.Change(apiValue: nil) == .other)
    }

    @Test("A response that is not a list of files is an error, not an empty diff")
    func notAList() {
        #expect(throws: GitHubError.self) {
            try ChangedFilesQuery.files(from: Data(#"{"message":"Not Found"}"#.utf8))
        }
    }

    /// Verified against GitHub: the anchor is the SHA-256 of the path.
    @Test("A file links to its own place in the diff")
    func anchor() throws {
        let file = ChangedFile(
            path: "core/module_gdpr/src/ReportConfiguration/ReportCfgChecklistGdprProcedure.php",
            additions: 1, deletions: 1, change: .modified, patch: nil
        )
        let url = try #require(file.url(
            pullRequest: URL(string: "https://github.com/octo/platform/pull/35611")!
        ))
        #expect(url.absoluteString == "https://github.com/octo/platform/pull/35611/files"
            + "#diff-aa74b23405124edd5048e39db9b14f47dcb8a1c4346cfd33533c9eaf4f8209af")
    }

    @Test("A path is shortened to the part worth reading")
    func shortPath() {
        let deep = ChangedFile(
            path: "core/module_system/src/System/Thing.php",
            additions: 0, deletions: 0, change: .modified, patch: nil
        )
        #expect(deep.shortPath == "System/Thing.php")

        let flat = ChangedFile(path: "README.md", additions: 0, deletions: 0, change: .modified, patch: nil)
        #expect(flat.shortPath == "README.md")
    }

    @Test("A repository is split the way every item carries it")
    func repository() {
        let parts = ChangedFilesQuery.repository("octo/platform")
        #expect(parts?.owner == "octo")
        #expect(parts?.name == "platform")
        #expect(ChangedFilesQuery.repository("octo") == nil)
    }
}

/// Why the patch is copied once on its way in.
///
/// `JSONSerialization` hands back strings that are `NSString`
/// underneath. Swift calls those foreign, and on one of them every
/// character access is a message send and every hash normalises the text
/// first. `DiffCache` is keyed by the patch itself and the view body
/// looks a file up several times a frame, so the cache that exists to
/// make scrolling cheap was the expensive part: measured on a six-file
/// review of 95 KB, one pass of those lookups took 2.94 ms as the
/// strings arrived and 0.093 ms once they were native.
@Suite("A patch is a Swift string by the time anything reads it")
struct PatchStorageTests {
    private func answer(_ patch: String) -> Data {
        let node: [[String: Any]] = [[
            "filename": "src/Thing.php",
            "status": "modified",
            "additions": 1,
            "deletions": 0,
            "changes": 1,
            "patch": patch,
        ]]
        return try! JSONSerialization.data(withJSONObject: node)
    }

    private func isNative(_ text: String) -> Bool {
        text.utf8.withContiguousStorageIfAvailable { _ in true } ?? false
    }

    /// The check that matters. It is about *how* the text is stored, not
    /// what it says, so nothing else here can stand in for it.
    @Test("The patch comes back as contiguous UTF-8")
    func contiguous() throws {
        let read = try ChangedFilesQuery.files(from: answer("@@ -1 +1 @@\n-one\n+two\n"))

        let patch = try #require(read.first?.patch)
        #expect(isNative(patch))
    }

    /// The parsing this sits next to, which must not have changed.
    @Test("Windows endings are still taken off")
    func endings() throws {
        let read = try ChangedFilesQuery.files(from: answer("@@ -1 +1 @@\r\n-one\r\n+two\r\n"))

        let patch = try #require(read.first?.patch)
        #expect(!patch.contains("\r"))
        #expect(patch.contains("-one"))
        #expect(isNative(patch))
    }

    /// Text that is not plain ASCII takes a different path through the
    /// copy, and a patch of a German source file is full of it.
    @Test("Something other than ASCII survives the copy")
    func beyondASCII() throws {
        let read = try ChangedFilesQuery.files(
            from: answer("@@ -1 +1 @@\n-Gr\u{00f6}\u{00df}e\n+Ma\u{00df}e \u{1F600}\n")
        )

        let patch = try #require(read.first?.patch)
        #expect(patch.contains("Gr\u{00f6}\u{00df}e"))
        #expect(patch.contains("\u{1F600}"))
        #expect(isNative(patch))
    }
}

@MainActor
@Suite("A diff that is open stays open")
struct OpenedDiffTests {
    private let list = SavedList(
        id: "reviews", title: "Reviews", query: "is:pr review-requested:@me",
        content: .pullRequests
    )

    private func item(_ id: String) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com/octo/platform/pull/1")!,
            isDraft: false, updatedAt: .now, reviewDecision: .none, checks: .none
        )
    }

    private func file(_ path: String) -> ChangedFile {
        ChangedFile(path: path, additions: 1, deletions: 0, change: .modified, patch: "@@")
    }

    private func state() -> AppState {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        state.settings.savedLists = [list]
        state.listPullRequests[list.id] = [item("1")]
        state.changedFiles["1"] = .loaded([file("a.php"), file("b.php")])
        return state
    }

    /// The bug this guards: the overlay used to read its files out of
    /// `changedFiles`, which every refresh rebuilds -- so a refresh arriving
    /// while someone read a diff took the diff away from under them.
    @Test("A refresh rebuilding the file cache does not touch an open diff")
    func survivesRefresh() {
        let state = state()
        guard case .loaded(let files) = state.changedFiles["1"] else {
            Issue.record("expected files")
            return
        }
        state.openDiff(OpenedDiff(
            pullRequestID: "1", path: "a.php", files: files,
            url: URL(string: "https://github.com/octo/platform/pull/1")!
        ))

        // What a refresh does to that dictionary, in both the shapes it
        // takes: replaced wholesale, and pruned of a row that has gone.
        state.changedFiles = [:]
        #expect(state.openedDiffs.first?.files.count == 2)

        state.listPullRequests[list.id] = []
        #expect(state.openedDiffs.first?.files.count == 2)
        // And the links still work, though the row is gone.
        #expect(state.openedDiffs.first?.url.lastPathComponent == "1")
    }
}
