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

@Suite("The tree, flattened into rows")
struct FileTreeRowTests {
    private func files(_ paths: [String]) -> [ChangedFile] {
        paths.map {
            ChangedFile(path: $0, additions: 1, deletions: 0, change: .modified, patch: "@@")
        }
    }

    /// Flattened rather than drawn as nested groups: a list that nests its
    /// own groups indents each level by an amount it does not offer to
    /// change, and six levels deep leaves a sliver for the file name.
    @Test("Every node gets a row, with how deep it sits")
    func depths() {
        let tree = FileTree.build(files(["a/b/one.php", "a/b/two.php", "a/c/three.php"]))
        let rows = FileTree.rows(tree)

        // `a` holds two folders, so it is a level of its own; the files
        // sit two levels under it.
        #expect(rows.first?.depth == 0)
        #expect(rows.first?.id == "d:a/")
        let deepest = rows.first { $0.id == "f:a/b/one.php" }
        #expect(deepest?.depth == 2)
    }

    /// What is under a shut folder is not drawn, but the folder still is.
    @Test("A shut folder keeps its own row and loses its children")
    func shut() {
        let tree = FileTree.build(files(["a/b/one.php", "a/c/two.php"]))
        let all = FileTree.rows(tree)
        let folded = FileTree.rows(tree, shut: ["a/b/"])

        #expect(folded.count == all.count - 1)
        #expect(folded.contains { $0.id == "d:a/b/" })
        #expect(!folded.contains { $0.id == "f:a/b/one.php" })
    }

    /// Shutting the root takes everything with it but itself.
    @Test("Shutting the top leaves one row")
    func shutRoot() {
        let tree = FileTree.build(files(["a/b/one.php", "a/c/two.php"]))
        #expect(FileTree.rows(tree, shut: ["a/"]).count == 1)
    }

    /// Depth-first, in the order of the tree: the list is read downwards
    /// and has to run the way the files do.
    @Test("The rows come out in the order the tree is in")
    func order() {
        let tree = FileTree.build(files(["a/one.php", "a/two.php", "b/three.php"]))
        let names = FileTree.rows(tree).map(\.id)
        #expect(names.firstIndex(of: "f:a/one.php")! < names.firstIndex(of: "f:a/two.php")!)
        #expect(names.firstIndex(of: "f:a/two.php")! < names.firstIndex(of: "f:b/three.php")!)
    }

    /// Files and folders can share a path in a flat list, so the two are
    /// told apart in the identity as well.
    @Test("A file and a folder of the same name are different rows")
    func identity() {
        let tree = FileTree.build(files(["x/one.php"]))
        let ids = Set(FileTree.rows(tree).map(\.id))
        #expect(ids.count == FileTree.rows(tree).count)
    }
}
