import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("The files, as a tree")
struct FileTreeTests {
    private func file(_ path: String, changed: Int = 2) -> ChangedFile {
        ChangedFile(
            path: path, additions: changed, deletions: 0, change: .modified, patch: "x"
        )
    }

    /// What a node renders as, so a test can read a tree at a glance.
    private func shape(_ nodes: [FileTree.Node]) -> [String] {
        nodes.map { node in
            switch node {
            case .file(let file): (file.path as NSString).lastPathComponent
            case .folder(let folder): "\(folder.name)/[" + shape(folder.children).joined(separator: " ") + "]"
            }
        }
    }

    @Test("Files in the same directory end up under it")
    func grouping() {
        let tree = FileTree.build([
            file("src/Filter/UserFilter.php"),
            file("src/Filter/GroupFilter.php"),
        ])
        #expect(shape(tree) == ["src/Filter/[UserFilter.php GroupFilter.php]"])
    }

    /// Three rows of triangle with one thing under each says nothing that
    /// one row saying "core/module_system/src" does not.
    @Test("A chain of single directories is written as one row")
    func collapsedChain() {
        let tree = FileTree.build([file("core/module_system/src/Thing.php")])
        #expect(shape(tree) == ["core/module_system/src/[Thing.php]"])
    }

    @Test("A chain stops collapsing where it branches")
    func branching() {
        let tree = FileTree.build([
            file("core/module_system/src/Filter/A.php"),
            file("core/module_system/src/Model/B.php"),
        ])
        #expect(shape(tree) == ["core/module_system/src/[Filter/[A.php] Model/[B.php]]"])
    }

    /// The files arrive biggest first, and the tree must not lose that: the
    /// folder holding the largest change still comes first.
    @Test("The order the files arrived in survives")
    func order() {
        let tree = FileTree.build([
            file("b/Big.php", changed: 400),
            file("a/Small.php", changed: 1),
            file("b/AlsoBig.php", changed: 300),
        ])
        #expect(shape(tree) == ["b/[Big.php AlsoBig.php]", "a/[Small.php]"])
    }

    @Test("A file at the root is a row of its own")
    func rootFile() {
        let tree = FileTree.build([file("README.md"), file("src/Thing.php")])
        #expect(shape(tree) == ["README.md", "src/[Thing.php]"])
    }

    /// A directory that holds both a file and a directory cannot collapse,
    /// or the file would lose the row it lives on.
    @Test("A directory holding a file as well as a directory stays put")
    func mixed() {
        let tree = FileTree.build([
            file("src/Thing.php"),
            file("src/Filter/Other.php"),
        ])
        #expect(shape(tree) == ["src/[Thing.php Filter/[Other.php]]"])
    }

    @Test("Nothing in, nothing out")
    func empty() {
        #expect(FileTree.build([]).isEmpty)
    }

    @Test("A folder knows every file below it")
    func filesBelow() throws {
        let tree = FileTree.build([
            file("src/Filter/A.php"),
            file("src/Model/B.php"),
        ])
        guard case .folder(let root) = try #require(tree.first) else {
            Issue.record("expected a folder")
            return
        }
        #expect(root.files.map(\.path) == ["src/Filter/A.php", "src/Model/B.php"])
    }

    /// The view opens every folder to begin with: a diff is read, not
    /// explored, and a tree that arrives shut is a tree to click open.
    @Test("Every folder is listed, so the view can open them all")
    func folderPaths() {
        let tree = FileTree.build([
            file("src/Filter/A.php"),
            file("src/Model/B.php"),
            file("README.md"),
        ])
        #expect(FileTree.folderPaths(tree) == ["src/", "src/Filter/", "src/Model/"])
    }
}
