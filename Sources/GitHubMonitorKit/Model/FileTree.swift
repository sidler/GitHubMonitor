import Foundation

/// The changed files, arranged as the directories they live in.
///
/// A flat list of thirty paths in a repository like this one is thirty lines
/// beginning "core/module_system/src/" -- the part that differs is at the
/// end, where it is hardest to scan. The tree puts the shared part once at
/// the top and leaves the names to line up under it.
public enum FileTree {
    public indirect enum Node: Identifiable, Hashable, Sendable {
        case folder(Folder)
        case file(ChangedFile)

        public var id: String {
            switch self {
            case .folder(let folder): "folder:" + folder.path
            case .file(let file): "file:" + file.path
            }
        }

        /// Nil for a file, which is what stops the outline drawing a
        /// disclosure triangle beside one.
        public var children: [Node]? {
            switch self {
            case .folder(let folder): folder.children
            case .file: nil
            }
        }
    }

    public struct Folder: Hashable, Sendable {
        /// The whole path down to here, which is what makes it unique.
        public let path: String
        /// What is drawn: several segments where a chain of directories has
        /// only one thing in it.
        public let name: String
        public let children: [Node]

        public init(path: String, name: String, children: [Node]) {
            self.path = path
            self.name = name
            self.children = children
        }

        /// Every file below this folder, however deep.
        public var files: [ChangedFile] {
            children.flatMap { child -> [ChangedFile] in
                switch child {
                case .file(let file): [file]
                case .folder(let folder): folder.files
                }
            }
        }
    }

    /// Builds the tree, keeping the order the files arrived in.
    ///
    /// That order is by size of change, so the folder holding the largest
    /// change comes first and the question "where is the work" survives the
    /// grouping.
    public static func build(_ files: [ChangedFile]) -> [Node] {
        build(files, prefix: "")
    }

    private static func build(_ files: [ChangedFile], prefix: String) -> [Node] {
        var order: [String] = []
        var groups: [String: [ChangedFile]] = [:]
        var leaves: [String: ChangedFile] = [:]

        for file in files {
            let rest = file.path.dropFirst(prefix.count)
            let segments = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            let head = String(segments[0])

            if groups[head] == nil, leaves[head] == nil { order.append(head) }
            if segments.count > 1 {
                groups[head, default: []].append(file)
            } else {
                leaves[head] = file
            }
        }

        return order.map { head in
            if let file = leaves[head] {
                return .file(file)
            }
            let path = prefix + head + "/"
            let children = build(groups[head] ?? [], prefix: path)
            // A directory holding nothing but one directory is written as
            // one line: "core/module_system/src" rather than three rows of
            // triangle with one thing under each.
            if children.count == 1, case .folder(let only) = children[0] {
                return .folder(Folder(
                    path: only.path,
                    name: head + "/" + only.name,
                    children: only.children
                ))
            }
            return .folder(Folder(path: path, name: head, children: children))
        }
    }

    /// Every folder in the tree, by path -- what the view needs to open them
    /// all to begin with.
    public static func folderPaths(_ nodes: [Node]) -> Set<String> {
        var paths: Set<String> = []
        for node in nodes {
            guard case .folder(let folder) = node else { continue }
            paths.insert(folder.path)
            paths.formUnion(folderPaths(folder.children))
        }
        return paths
    }
}
