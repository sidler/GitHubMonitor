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
    @Test("The biggest change comes first")
    func order() throws {
        let files = try ChangedFilesQuery.files(from: payload([
            file("small.php", additions: 1, deletions: 0),
            file("huge.php", additions: 300, deletions: 100),
            file("middle.php", additions: 10, deletions: 10),
        ]))
        #expect(files.map(\.path) == ["huge.php", "middle.php", "small.php"])
        #expect(files.first?.changedLines == 400)
    }

    @Test("Files of equal size are ordered by path")
    func tie() throws {
        let files = try ChangedFilesQuery.files(from: payload([
            file("b.php", additions: 2, deletions: 0),
            file("a.php", additions: 1, deletions: 1),
        ]))
        #expect(files.map(\.path) == ["a.php", "b.php"])
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
